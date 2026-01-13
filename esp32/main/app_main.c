// ===============================
// OPTIPARK Gate ESP32 (ESP-IDF)
// TCP receiver (from ESP32-CAM) + LCD + Servo
// Uses Avinashee lcd_i2c library (PCF8574)
// ===============================

#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <inttypes.h>
#include <errno.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"

#include "esp_log.h"
#include "esp_event.h"
#include "esp_timer.h"
#include "nvs_flash.h"

#include "esp_netif.h"
#include "esp_wifi.h"
#include "mqtt_client.h"

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_adc/adc_oneshot.h"

#include "lwip/sockets.h"
#include "lwip/netdb.h"
#include "lwip/inet.h"

// ---- LCD LIB (Avinashee) ----
#include "lcd_i2c.h"

// ============================================================
// LOG TAG
// ============================================================
static const char *TAG = "PARKING";

// ============================================================
// WIFI CONFIG (STA)
// ============================================================
#define WIFI_SSID "SSID"
#define WIFI_PASS "PASSWORD"

// ============================================================
// TCP SERVER
// ============================================================
#define TCP_LISTEN_PORT  3333
#define TCP_RX_BUF_SIZE  256

// ============================================================
// MQTT CONFIG
// ============================================================
#define MQTT_URI  "mqtt://BROKER_IP:1883"

// ============================================================
// PARKING CONFIG
// ============================================================
#define PARKING_ID        "nice_sophia.A"
#define MQTT_TOPIC_SPOTS  "parking/nice_sophia.A/status"
#define MQTT_TOPIC_RAIN   "parking/rain"

// ============================================================
// SPOTS CONFIG
// ============================================================
#define N_SPOTS 5
static const char *SLOT_IDS[N_SPOTS] = { "A-3", "A-2", "A-20", "A-18", "A-10" };

static const gpio_num_t IR_PINS[N_SPOTS] = {
    GPIO_NUM_32, GPIO_NUM_33, GPIO_NUM_34, GPIO_NUM_35, GPIO_NUM_27
};
static const bool IR_ACTIVE_LOW = true;

static const gpio_num_t LED_GREEN[N_SPOTS] = {
    GPIO_NUM_25, GPIO_NUM_26, GPIO_NUM_14, GPIO_NUM_16, GPIO_NUM_17
};
static const gpio_num_t LED_BLUE[N_SPOTS] = {
    GPIO_NUM_4, GPIO_NUM_5, GPIO_NUM_18, GPIO_NUM_19, GPIO_NUM_23
};

#define LED_ON_LEVEL   0   // common anode
#define LED_OFF_LEVEL  1

// ============================================================
// TIMING / MQTT
// ============================================================
#define READ_EVERY_MS             150
#define PUBLISH_QOS               1
#define PUBLISH_RETAIN            1
#define PUBLISH_ON_CHANGE_ONLY    1
#define RAIN_PUBLISH_ON_CHANGE_ONLY  1

// ============================================================
// SOFTWARE PWM (spot LEDs)
// ============================================================
#define PWM_STEPS    50
#define PWM_TICK_US  200
#define BRIGHTNESS_STEPS  5

static esp_timer_handle_t s_pwm_timer = NULL;
static volatile uint32_t s_pwm_phase = 0;
static volatile uint8_t s_green_duty[N_SPOTS] = {0};
static volatile uint8_t s_blue_duty[N_SPOTS]  = {0};

// ============================================================
// RAIN SENSOR (ADC)
// ============================================================
#define RAIN_ADC_UNIT      ADC_UNIT_1
#define RAIN_ADC_CHANNEL   ADC_CHANNEL_0   // GPIO36
#define RAIN_ADC_ATTEN     ADC_ATTEN_DB_11
#define RAIN_ADC_BITWIDTH  ADC_BITWIDTH_DEFAULT

#define RAIN_WET_RAW        1200
#define RAIN_DRY_RAW        3500
#define RAIN_RAW_THRESHOLD  2500

#define RAIN_SENSOR_ID "rain-1"
static adc_oneshot_unit_handle_t s_adc = NULL;

// ============================================================
// WIFI EVENT GROUP
// ============================================================
static EventGroupHandle_t s_wifi_event_group;
#define WIFI_CONNECTED_BIT BIT0

// ============================================================
// MQTT STATE
// ============================================================
static esp_mqtt_client_handle_t s_mqtt_client = NULL;
static volatile bool s_mqtt_connected = false;

// ============================================================
// STATE
// ============================================================
static bool s_occ[N_SPOTS] = {0};
static bool s_occ_prev[N_SPOTS] = {0};

static int s_rain01 = 0;
static int s_rain01_prev = -1;

// ============================================================
// SERVO + LCD + QR logic
// ============================================================

// QR format: OPK_V1_20JA02|OPTIPARK:A-1:Ons Bahri
#define QR_EXPECTED_SIGNATURE "OPK_V1_20JA02"
#define QR_EXPECTED_ZONE      'A'   // this ESP controls gate A

// ---- SERVO ----
#define SERVO_GPIO          GPIO_NUM_13
#define SERVO_LEDC_TIMER    LEDC_TIMER_1
#define SERVO_LEDC_MODE     LEDC_LOW_SPEED_MODE
#define SERVO_LEDC_CHANNEL  LEDC_CHANNEL_4
#define SERVO_FREQ_HZ       50
#define SERVO_RES_BITS      LEDC_TIMER_16_BIT

#define SERVO_PULSE_MIN_US  1000
#define SERVO_PULSE_MAX_US  2000
#define SERVO_OPEN_DEG      0   
#define SERVO_CLOSE_DEG     90   
#define SERVO_OPEN_MS       2500

#define GATE_COOLDOWN_MS    5000
static volatile bool s_gate_busy = false;
static int64_t s_gate_last_action_ms = 0;
static char s_last_qr[160] = {0};

// LCD (your working test values)
#define LCD_COLS 16
#define LCD_ROWS 2

// ============================================================
// Helpers
// ============================================================
static inline int64_t now_ms(void) { return esp_timer_get_time() / 1000; }

static inline int clampi(int x, int a, int b) {
    if (x < a) return a;
    if (x > b) return b;
    return x;
}

static bool read_occupied(int i) {
    int v = gpio_get_level(IR_PINS[i]);
    return IR_ACTIVE_LOW ? (v == 0) : (v == 1);
}

static void set_spot_led_pwm(int i, bool occupied) {
    if (occupied) { s_green_duty[i] = 0;                s_blue_duty[i]  = BRIGHTNESS_STEPS; }
    else          { s_green_duty[i] = BRIGHTNESS_STEPS; s_blue_duty[i]  = 0; }
}

static int count_free(void) {
    int freeCount = 0;
    for (int i = 0; i < N_SPOTS; i++) if (!s_occ[i]) freeCount++;
    return freeCount;
}

// ============================================================
// LCD helpers (Avinashee)
// ============================================================
static void lcd_print_padded_16(const char *s) {
    char buf[17];
    memset(buf, ' ', 16);
    buf[16] = 0;
    size_t n = strlen(s);
    if (n > 16) n = 16;
    memcpy(buf, s, n);
    send_string(buf);
}

static void lcd_line0_optipark(void) {
    setCursor(0, 0);
    lcd_print_padded_16("OPTIPARK");
}

static void lcd_show_waiting(void) {
    lcd_line0_optipark();
    setCursor(0, 1);
    lcd_print_padded_16("Waiting...");
}

static void lcd_show_invalid(void) {
    lcd_line0_optipark();
    setCursor(0, 1);
    lcd_print_padded_16("Invalid QR");
}

static void show_wrong_parking(const char *zone) {
    lcd_line0_optipark();
    setCursor(0, 1);
    if (zone && zone[0] == 'B') lcd_print_padded_16("Go to parking B");
    else lcd_print_padded_16("Wrong parking");
}

static void show_welcome(const char *name) {
    lcd_line0_optipark();
    setCursor(0, 1);
    lcd_print_padded_16("Welcome");
    vTaskDelay(pdMS_TO_TICKS(800));
    lcd_line0_optipark();
    setCursor(0, 1);
    lcd_print_padded_16(name ? name : "User");
}

// ============================================================
// SERVO (LEDC)
// ============================================================
static uint32_t servo_us_to_duty(uint32_t us) {
    const uint32_t period_us = 1000000UL / SERVO_FREQ_HZ; // 20ms
    const uint32_t max_duty = (1UL << SERVO_RES_BITS) - 1;
    return (us * max_duty) / period_us;
}

static uint32_t servo_angle_to_us(int deg) {
    if (deg < 0) deg = 0;
    if (deg > 180) deg = 180;
    return SERVO_PULSE_MIN_US + (uint32_t)((SERVO_PULSE_MAX_US - SERVO_PULSE_MIN_US) * (uint32_t)deg / 180UL);
}

static void servo_set_angle(int deg) {
    uint32_t us = servo_angle_to_us(deg);
    uint32_t duty = servo_us_to_duty(us);
    ledc_set_duty(SERVO_LEDC_MODE, SERVO_LEDC_CHANNEL, duty);
    ledc_update_duty(SERVO_LEDC_MODE, SERVO_LEDC_CHANNEL);
}

static void servo_init(void) {
    ledc_timer_config_t tcfg = {
        .speed_mode = SERVO_LEDC_MODE,
        .duty_resolution = SERVO_RES_BITS,
        .timer_num = SERVO_LEDC_TIMER,
        .freq_hz = SERVO_FREQ_HZ,
        .clk_cfg = LEDC_AUTO_CLK
    };
    ESP_ERROR_CHECK(ledc_timer_config(&tcfg));

    ledc_channel_config_t ccfg = {
        .gpio_num = SERVO_GPIO,
        .speed_mode = SERVO_LEDC_MODE,
        .channel = SERVO_LEDC_CHANNEL,
        .timer_sel = SERVO_LEDC_TIMER,
        .duty = 0,
        .hpoint = 0
    };
    ESP_ERROR_CHECK(ledc_channel_config(&ccfg));

    servo_set_angle(SERVO_CLOSE_DEG);
    ESP_LOGI(TAG, "Servo ready on GPIO%d", (int)SERVO_GPIO);
}

static void gate_open_close(void) {
    s_gate_busy = true;
    servo_set_angle(SERVO_OPEN_DEG);
    vTaskDelay(pdMS_TO_TICKS(SERVO_OPEN_MS));
    servo_set_angle(SERVO_CLOSE_DEG);
    s_gate_busy = false;
    s_gate_last_action_ms = now_ms();
}

// ============================================================
// QR parsing
// ============================================================
static bool parse_qr_payload(const char *in, char *out_name, size_t out_name_sz,
                             char *out_zone, size_t out_zone_sz)
{
    // OPK_V1_20JA02|OPTIPARK:A-1:Name
    if (!in || !out_name || !out_zone) return false;

    const char *p1 = strchr(in, '|');
    if (!p1) return false;

    size_t sig_len = (size_t)(p1 - in);
    if (sig_len == 0 || sig_len >= 32) return false;

    char sig[32];
    memcpy(sig, in, sig_len);
    sig[sig_len] = 0;
    if (strcmp(sig, QR_EXPECTED_SIGNATURE) != 0) return false;

    const char *rest = p1 + 1; // OPTIPARK:A-1:Name
    const char *c1 = strchr(rest, ':');
    if (!c1) return false;
    if (strncmp(rest, "OPTIPARK", 7) != 0) return false;

    const char *zone_ptr = c1 + 1;
    const char *zone_end = strchr(zone_ptr, '-');
    if (!zone_end) return false;

    size_t zone_len = (size_t)(zone_end - zone_ptr);
    if (zone_len == 0 || zone_len >= out_zone_sz) return false;
    memcpy(out_zone, zone_ptr, zone_len);
    out_zone[zone_len] = 0;

    const char *last_colon = strrchr(in, ':');
    if (!last_colon) return false;
    const char *name_ptr = last_colon + 1;
    if (*name_ptr == 0) return false;

    snprintf(out_name, out_name_sz, "%s", name_ptr);
    return true;
}

// ============================================================
// TCP server task
// ============================================================
static int recv_line(int sock, char *out, int out_sz)
{
    int idx = 0;
    while (idx < out_sz - 1) {
        char c;
        int r = recv(sock, &c, 1, 0);
        if (r == 0) return 0;
        if (r < 0) return -1;
        if (c == '\r') continue;
        if (c == '\n') break;
        out[idx++] = c;
    }
    out[idx] = 0;
    return idx;
}

static void handle_qr_payload(const char *payload)
{
    if (!payload || payload[0] == 0) return;

    int64_t t = now_ms();

    if (s_gate_busy) {
        ESP_LOGW(TAG, "Gate busy, ignore");
        return;
    }
    if ((t - s_gate_last_action_ms) < GATE_COOLDOWN_MS) {
        ESP_LOGW(TAG, "Gate cooldown, ignore");
        return;
    }
    if (strncmp(payload, s_last_qr, sizeof(s_last_qr)) == 0) {
        ESP_LOGW(TAG, "Same QR repeated, ignore");
        return;
    }
    strncpy(s_last_qr, payload, sizeof(s_last_qr) - 1);

    ESP_LOGI(TAG, "QR RX: %s", payload);

    char name[64] = {0};
    char zone[8]  = {0};

    if (!parse_qr_payload(payload, name, sizeof(name), zone, sizeof(zone))) {
        lcd_show_invalid();
        vTaskDelay(pdMS_TO_TICKS(1200));
        lcd_show_waiting();
        return;
    }

    if (zone[0] != QR_EXPECTED_ZONE) {
        show_wrong_parking(zone);
        vTaskDelay(pdMS_TO_TICKS(2000));
        lcd_show_waiting();
        return;
    }

    show_welcome(name);
    gate_open_close();
    lcd_show_waiting();
}

static void tcp_server_task(void *arg)
{
    (void)arg;

    int listen_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
    if (listen_fd < 0) {
        ESP_LOGE(TAG, "socket() failed: errno=%d", errno);
        vTaskDelete(NULL);
        return;
    }

    int opt = 1;
    setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(TCP_LISTEN_PORT);

    if (bind(listen_fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        ESP_LOGE(TAG, "bind() failed: errno=%d", errno);
        close(listen_fd);
        vTaskDelete(NULL);
        return;
    }

    if (listen(listen_fd, 2) != 0) {
        ESP_LOGE(TAG, "listen() failed: errno=%d", errno);
        close(listen_fd);
        vTaskDelete(NULL);
        return;
    }

    ESP_LOGI(TAG, "TCP server listening on port %d", TCP_LISTEN_PORT);

    while (1) {
        struct sockaddr_in6 source_addr;
        socklen_t socklen = sizeof(source_addr);
        int sock = accept(listen_fd, (struct sockaddr *)&source_addr, &socklen);
        if (sock < 0) {
            ESP_LOGE(TAG, "accept() failed: errno=%d", errno);
            vTaskDelay(pdMS_TO_TICKS(200));
            continue;
        }

        ESP_LOGI(TAG, "TCP client connected");

        char line[TCP_RX_BUF_SIZE];
        while (1) {
            int n = recv_line(sock, line, sizeof(line));
            if (n == 0) {
                ESP_LOGI(TAG, "TCP client disconnected");
                break;
            }
            if (n < 0) {
                ESP_LOGE(TAG, "recv() error: errno=%d", errno);
                break;
            }

            while (n > 0 && (line[n-1] == ' ' || line[n-1] == '\t')) line[--n] = 0;

            ESP_LOGI(TAG, "TCP RX line (%d): '%s'", n, line);
            handle_qr_payload(line);
        }

        shutdown(sock, 0);
        close(sock);
    }
}

// ============================================================
// Rain ADC
// ============================================================
static void rain_adc_init(void)
{
    adc_oneshot_unit_init_cfg_t unit_cfg = {
        .unit_id = RAIN_ADC_UNIT,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&unit_cfg, &s_adc));

    adc_oneshot_chan_cfg_t chan_cfg = {
        .bitwidth = RAIN_ADC_BITWIDTH,
        .atten = RAIN_ADC_ATTEN,
    };
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, RAIN_ADC_CHANNEL, &chan_cfg));
}

static int rain_adc_read_raw(void)
{
    int raw = 0;
    if (adc_oneshot_read(s_adc, RAIN_ADC_CHANNEL, &raw) != ESP_OK) return -1;
    return raw;
}

static int rain01_from_raw(int raw)
{
    if (raw < 0) return 0;
    raw = clampi(raw, RAIN_WET_RAW, RAIN_DRY_RAW);
    return (raw <= RAIN_RAW_THRESHOLD) ? 1 : 0;
}

// ============================================================
// MQTT publish
// ============================================================
static void publish_spot(int i, bool occupied)
{
    if (!s_mqtt_connected || !s_mqtt_client) return;

    char payload[220];
    snprintf(payload, sizeof(payload),
             "{\"parking_id\":\"%s\",\"slot_id\":\"%s\",\"occupied\":%s,\"ts_ms\":%" PRId64 "}",
             PARKING_ID, SLOT_IDS[i], occupied ? "true" : "false", now_ms());

    esp_mqtt_client_publish(s_mqtt_client, MQTT_TOPIC_SPOTS, payload, 0, PUBLISH_QOS, PUBLISH_RETAIN);
}

static void publish_rain01_as_rain_pct(int rain01)
{
    if (!s_mqtt_connected || !s_mqtt_client) return;

    char payload[96];
    snprintf(payload, sizeof(payload),
             "{\"sensor_id\":\"%s\",\"rain_pct\":%d}",
             RAIN_SENSOR_ID, rain01);

    esp_mqtt_client_publish(s_mqtt_client, MQTT_TOPIC_RAIN, payload, 0, PUBLISH_QOS, PUBLISH_RETAIN);
}

// ============================================================
// Software PWM timer (spot LEDs)
// ============================================================
static void pwm_timer_cb(void *arg)
{
    (void)arg;
    uint32_t phase = s_pwm_phase + 1;
    if (phase >= PWM_STEPS) phase = 0;
    s_pwm_phase = phase;

    for (int i = 0; i < N_SPOTS; i++) {
        uint8_t gd = s_green_duty[i];
        uint8_t bd = s_blue_duty[i];

        bool green_on = (gd > 0) && (phase < gd);
        bool blue_on  = (bd > 0) && (phase < bd);

        if (green_on) blue_on = false;
        if (blue_on)  green_on = false;

        gpio_set_level(LED_GREEN[i], green_on ? LED_ON_LEVEL : LED_OFF_LEVEL);
        gpio_set_level(LED_BLUE[i],  blue_on  ? LED_ON_LEVEL : LED_OFF_LEVEL);
    }
}

static void pwm_start(void)
{
    const esp_timer_create_args_t targs = {
        .callback = &pwm_timer_cb,
        .arg = NULL,
        .dispatch_method = ESP_TIMER_TASK,
        .name = "soft_pwm"
    };
    ESP_ERROR_CHECK(esp_timer_create(&targs, &s_pwm_timer));
    ESP_ERROR_CHECK(esp_timer_start_periodic(s_pwm_timer, PWM_TICK_US));
}

// ============================================================
// Wi-Fi
// ============================================================
static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        ESP_LOGW(TAG, "Wi-Fi disconnected, retrying...");
        esp_wifi_connect();
        xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)data;
        ESP_LOGI(TAG, "Wi-Fi IP=" IPSTR, IP2STR(&event->ip_info.ip));
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

static void wifi_init_sta(void)
{
    s_wifi_event_group = xEventGroupCreate();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL));

    wifi_config_t wifi_config = {0};
    strncpy((char *)wifi_config.sta.ssid, WIFI_SSID, sizeof(wifi_config.sta.ssid));
    strncpy((char *)wifi_config.sta.password, WIFI_PASS, sizeof(wifi_config.sta.password));
    wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());

    ESP_LOGI(TAG, "Connecting Wi-Fi SSID=%s ...", WIFI_SSID);
    xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT, pdFALSE, pdTRUE, portMAX_DELAY);
}

// ============================================================
// MQTT
// ============================================================
static void mqtt_event_handler(void *args, esp_event_base_t base, int32_t id, void *data)
{
    (void)args; (void)base;
    switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED:
        s_mqtt_connected = true;
        ESP_LOGI(TAG, "MQTT connected");
        break;
    case MQTT_EVENT_DISCONNECTED:
        s_mqtt_connected = false;
        ESP_LOGW(TAG, "MQTT disconnected");
        break;
    default:
        break;
    }
}

static void mqtt_start(void)
{
    esp_mqtt_client_config_t mqtt_cfg = {
        .broker.address.uri = MQTT_URI,
        .session.keepalive = 30,
        .network.reconnect_timeout_ms = 5000,
    };

    s_mqtt_client = esp_mqtt_client_init(&mqtt_cfg);
    ESP_ERROR_CHECK(esp_mqtt_client_register_event(s_mqtt_client, ESP_EVENT_ANY_ID, mqtt_event_handler, NULL));
    ESP_ERROR_CHECK(esp_mqtt_client_start(s_mqtt_client));
}

// ============================================================
// GPIO init (spots)
// ============================================================
static void gpio_init_all(void)
{
    for (int i = 0; i < N_SPOTS; i++) {
        gpio_config_t in_cfg = {
            .pin_bit_mask = 1ULL << IR_PINS[i],
            .mode = GPIO_MODE_INPUT,
            .pull_up_en = GPIO_PULLUP_DISABLE,
            .pull_down_en = GPIO_PULLDOWN_DISABLE,
            .intr_type = GPIO_INTR_DISABLE
        };
        ESP_ERROR_CHECK(gpio_config(&in_cfg));
    }

    uint64_t mask = 0;
    for (int i = 0; i < N_SPOTS; i++) {
        mask |= (1ULL << LED_GREEN[i]);
        mask |= (1ULL << LED_BLUE[i]);
    }

    gpio_config_t out_cfg = {
        .pin_bit_mask = mask,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE
    };
    ESP_ERROR_CHECK(gpio_config(&out_cfg));

    for (int i = 0; i < N_SPOTS; i++) {
        gpio_set_level(LED_GREEN[i], LED_OFF_LEVEL);
        gpio_set_level(LED_BLUE[i],  LED_OFF_LEVEL);
    }
}

// ============================================================
// Parking task (spots + rain)
// ============================================================
static void parking_task(void *arg)
{
    (void)arg;
    for (int i = 0; i < N_SPOTS; i++) s_occ_prev[i] = !s_occ[i];

    while (1) {
        int rain_raw = rain_adc_read_raw();
        s_rain01 = rain01_from_raw(rain_raw);

#if RAIN_PUBLISH_ON_CHANGE_ONLY
        if (s_rain01 != s_rain01_prev) {
            ESP_LOGI(TAG, "Rain change: raw=%d => %d", rain_raw, s_rain01);
            publish_rain01_as_rain_pct(s_rain01);
            s_rain01_prev = s_rain01;
        }
#else
        publish_rain01_as_rain_pct(s_rain01);
        s_rain01_prev = s_rain01;
#endif

        for (int i = 0; i < N_SPOTS; i++) {
            s_occ[i] = read_occupied(i);
            set_spot_led_pwm(i, s_occ[i]);
        }

        for (int i = 0; i < N_SPOTS; i++) {
#if PUBLISH_ON_CHANGE_ONLY
            if (s_occ[i] != s_occ_prev[i]) {
                publish_spot(i, s_occ[i]);
                s_occ_prev[i] = s_occ[i];
            }
#else
            publish_spot(i, s_occ[i]);
            s_occ_prev[i] = s_occ[i];
#endif
        }

        static int tick = 0;
        tick++;
        if (tick % (1000 / READ_EVERY_MS) == 0) {
            ESP_LOGI(TAG, "Free=%d/%d", count_free(), N_SPOTS);
        }

        vTaskDelay(pdMS_TO_TICKS(READ_EVERY_MS));
    }
}

// ============================================================
// app_main
// ============================================================
void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    }

    gpio_init_all();
    pwm_start();
    rain_adc_init();

    // ---- LCD init using your working library ----
    lcd_init(LCD_COLS, LCD_ROWS);
    backlight();
    clear();
    lcd_show_waiting();

    // ---- Servo ----
    servo_init();

    // ---- Wi-Fi + MQTT ----
    wifi_init_sta();
    mqtt_start();

    // ---- TCP server ----
    xTaskCreate(tcp_server_task, "tcp_server", 6144, NULL, 7, NULL);

    // ---- Parking logic ----
    xTaskCreate(parking_task, "parking_task", 7168, NULL, 5, NULL);
}
