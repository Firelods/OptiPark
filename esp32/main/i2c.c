/* @file  i2c.c
   @brief source code for basic i2c level operations
   @author Avinashee Tech
*/

#include <stdio.h>
#include "driver/gpio.h"
#include "driver/i2c.h"
#include "esp_log.h"
#include "esp_system.h"
#include "i2c.h"

#define I2C_Timeout		200
#define I2C_MASTER_SDA_IO   GPIO_NUM_21       
#define I2C_MASTER_SCL_IO   GPIO_NUM_22
#define I2C_MASTER_FREQ_HZ  100000              //100khz    
#define I2C_TX_BUF_DISABLE  	0                /*!< I2C master do not need buffer */
#define I2C_RX_BUF_DISABLE  	0                /*!< I2C master do not need buffer */
// I2C common protocol defines
#define WRITE_BIT                          I2C_MASTER_WRITE /*!< I2C master write */
#define READ_BIT                           I2C_MASTER_READ  /*!< I2C master read */
#define ACK_CHECK_EN                       0x1              /*!< I2C master will check ack from slave*/
#define ACK_CHECK_DIS                      0x0              /*!< I2C master will not check ack from slave */
#define ACK_VAL                            0x0              /*!< I2C ack value */
#define NACK_VAL                           0x1              /*!< I2C nack value */

esp_err_t error_code;
i2c_port_t i2c_port = I2C_NUM_0;
const char *I2C_TAG = "ESP32_LCD_I2C";

/**  
* @brief initializing bus parameters
* @retval parameter configuration status
* @param None
*/
int i2c_init(void){
    i2c_mode_t i2c_mode = I2C_MODE_MASTER;
    
    i2c_config_t conf = {
     .mode = I2C_MODE_MASTER,
     .sda_io_num = I2C_MASTER_SDA_IO,         // select GPIO specific to your project
     .sda_pullup_en = GPIO_PULLUP_ENABLE,
     .scl_io_num = I2C_MASTER_SCL_IO,         // select GPIO specific to your project
     .scl_pullup_en = GPIO_PULLUP_ENABLE,
     .master.clk_speed = I2C_MASTER_FREQ_HZ,  // select frequency specific to your project
    // .clk_flags = 0,          /*!< Optional, you can use I2C_SCLK_SRC_FLAG_* flags to choose i2c source clock here. */

    };

    i2c_param_config(i2c_port,&conf);
    return i2c_driver_install(i2c_port, I2C_MODE_MASTER,
                          I2C_RX_BUF_DISABLE, I2C_TX_BUF_DISABLE, 0);   
}


/**
 * @brief write byte data to slave device
 *        the data will be stored in slave buffer.
 *        can be read from slave buffer.
 *
 * ___________________________________________________________________
 * | start | slave_addr + wr_bit + ack | write n bytes + ack  | stop |
 * --------|---------------------------|----------------------|------|
 *
 * @retval command status 
 * @note cannot use master write slave on esp32c3 because there is only one i2c controller on esp32c3
 */
esp_err_t master_write_slave(uint8_t data,uint8_t i2c_addr){
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();    //Create a command link 
    i2c_master_start(cmd);    //start bit
    i2c_master_write_byte(cmd,(i2c_addr<<1)|WRITE_BIT,ACK_CHECK_DIS);   //write slave address and ensure to receive ACK 
    i2c_master_write_byte(cmd,data,ACK_CHECK_DIS);   //write data and ensure to receive ACK 
    i2c_master_stop(cmd);        //stop bit

    /*Trigger the execution of the command link by I2C controller
            Once the execution is triggered, the command link cannot be modified.*/
    error_code = i2c_master_cmd_begin(i2c_port,cmd,100/portTICK_PERIOD_MS);
    /*After the commands are transmitted, release the resources used by the command link*/
    i2c_cmd_link_delete(cmd);


    return error_code;


}

/**  
* @brief function to send i2c data 
* @retval None
* @param data i2c transmit data
* @param i2c_addr 7 bit slave address 
*/
void master_send_data(uint8_t data,uint8_t i2c_addr){
    error_code = master_write_slave(data,i2c_addr);
    if(error_code==ESP_OK){
#if DEBUG
    ESP_LOGI(I2C_TAG,"sent data");
#endif
    }
    else{
#if DEBUG
    ESP_LOGI(I2C_TAG,"data not sent");
#endif    
    }
}

