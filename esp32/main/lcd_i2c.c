/* @file  lcd_i2c.c
   @brief source code for operating 16x2 LCD with PCF8574 i2c expander
   @author Avinashee Tech
*/

#include "lcd_i2c.h"
//platform dependent headers
#include "i2c.h"
#include "esp_log.h"
#include "esp_err.h"
#include "esp_rom_sys.h"



//macros
#define DEBUG_I2c                     0                                       //enable to display message
#define LCD_I2C_ADDR                  0x27                                    //device 7 bit address
#define DELAY(microseconds)           (delay_us(microseconds))                //for delay in microseconds (platform dependent)
#define PRINT(fmt)                    (print_message(fmt))                    //print statement (platform dependent)
#define I2C_MASTER_SEND_DATA(...)     (master_send_data(__VA_ARGS__))         //i2c data function (platfrom dependent) in i2c.h
#define I2C_INIT(...)                 (i2c_init(##__VA_ARGS__))               //i2c initialize function (platfrom dependent) in i2c.h         

//variables
uint8_t lcd_error_code;
uint8_t _displayfunction = 0;
uint8_t _displaymode = 0;
uint8_t _displaycontrol = 0;
uint8_t _numlines = 0;
uint8_t _backlightval = LCD_NOBACKLIGHT;

/**  
* @brief delay function for lcd 
* @retval None
* @param us microseconds
*/
void delay_us(int us){
    esp_rom_delay_us(us);
}

/**  
* @brief function to print message
* @retval None
* @param format message to print
*/
void print_message(const char* msg){
    ESP_LOGI("ESP32_LCD", "%s", msg);
}


/**  
* @brief init i2c and display params
* @retval None
* @param lcd_cols number of LCD columns
* @param lcd_rows number of LCD rows
*/
void lcd_init(uint8_t lcd_cols,uint8_t lcd_rows){
    lcd_error_code = I2C_INIT();
    if(lcd_error_code==0){
#if DEBUG
      PRINT("I2C initialized");
#endif    
	}
    _displayfunction = LCD_4BITMODE | LCD_1LINE | LCD_5x8DOTS;
    lcd_begin(lcd_cols,lcd_rows,LCD_5x8DOTS);
}

/**  
* @brief LCD Display init sequence
* @retval None
* @param cols number of LCD columns
* @param lines number of LCD row lines
* @param dotsize number of dots or pixels for character pattern
*/
void lcd_begin(uint8_t cols, uint8_t lines, uint8_t dotsize){
    if (lines > 1) {
		_displayfunction |= LCD_2LINE;
	}
	_numlines = lines;

	// for some 1 line displays you can select a 10 pixel high font
	if ((dotsize != 0) && (lines == 1)) {
		_displayfunction |= LCD_5x10DOTS;
	}

	// Need at least 40ms after power rises above 2.7V before sending commands.
	DELAY(50000);	
  
	// Now we pull both RS and R/W low to begin commands
	expanderWrite(_backlightval);	// reset expander and turn backlight off (Bit 8 =1)
    DELAY(1000000);

  	//put the LCD into 4 bit mode

	// we start in 8bit mode, try to set 4 bit mode
    write4bits(0x03 << 4);
    DELAY(4500); // wait min 4.1ms
   
    // second attempt
    write4bits(0x03 << 4);
    DELAY(4500); // wait min 4.1ms
   
    // third go!
    write4bits(0x03 << 4); 
    DELAY(150);
   
    // finally, set to 4-bit interface
    write4bits(0x02 << 4); 

	// set lines, dotsize
	command(LCD_FUNCTIONSET | _displayfunction);  
	
	// turn the display on with no cursor or blinking default
	_displaycontrol = LCD_DISPLAYON | LCD_CURSOROFF | LCD_BLINKOFF;
	display();
	
	// clear it off
	clear();
	
	// Initialize to default text direction
	_displaymode = LCD_ENTRYLEFT | LCD_ENTRYSHIFTDECREMENT;
	
	// set the entry mode
	command(LCD_ENTRYMODESET | _displaymode);
	
	home();
}



/**  
* @brief LCD Display clear screen command
* @retval None
* @param None
* @note clear display, set cursor position to zero
*/
void clear(void){
	command(LCD_CLEARDISPLAY); 
	DELAY(2000); 
}

/**  
* @brief LCD Display home position command
* @retval None
* @param None
* @note set cursor position to zero
*/
void home(void){
	command(LCD_RETURNHOME); 
	DELAY(2000); 
}


/**  
* @brief LCD Display turn backlight on/off
* @retval None
* @param None
*/
void noBacklight(void) {
	_backlightval=LCD_NOBACKLIGHT;
	expanderWrite(0);
}
void backlight(void) {
	_backlightval=LCD_BACKLIGHT;
	expanderWrite(0);
}

/**  
* @brief LCD Display turn on/off command
* @retval None
* @param None
*/
void noDisplay(void) {
	_displaycontrol &= ~LCD_DISPLAYON;
	command(LCD_DISPLAYCONTROL | _displaycontrol);
}
void display(void) {
	_displaycontrol |= LCD_DISPLAYON;
	command(LCD_DISPLAYCONTROL | _displaycontrol);
}

/**  
* @brief LCD Display set cursor command
* @retval None
* @param None
*/
void setCursor(uint8_t col, uint8_t row){
	int row_offsets[] = { 0x00, 0x40, 0x14, 0x54 };
	if ( row > _numlines ) {
		row = _numlines-1;    // we count rows starting w/0
	}
	command(LCD_SETDDRAMADDR | (col + row_offsets[row]));
}


/**  
* @brief LCD Display custom character command
* @retval None
* @param None
* @note fill the first 8 CGRAM locations with custom characters
*/
void createChar(uint8_t location, uint8_t *charmap) {
	location &= 0x7; // we only have 8 locations 0-7
	command(LCD_SETCGRAMADDR | (location << 3));
	for (int i=0; i<8; i++) {
		lcd_write(charmap[i]);
	}
}

/**  
* @brief LCD Display commands
* @retval None
* @param None
*/
void command(uint8_t value) {
	lcd_send(value, 0);
}

/**  
* @brief LCD Display character codes
* @retval None
* @param None
*/
void lcd_write(uint8_t value) {
	lcd_send(value, Rs);
}

/**  
* @brief LCD Display send command/data
* @retval None
* @param value command or data byte
* @param mode RS pin status
* @note write either command or data based on RS pin value and resolve the byte value
        into two half bytes
*/
void lcd_send(uint8_t value, uint8_t mode) {
	uint8_t highnib=value&0xf0;
	uint8_t lownib=(value<<4)&0xf0;
    write4bits((highnib)|mode);
	write4bits((lownib)|mode); 
}

/**  
* @brief LCD Display send half byte
* @retval None
* @param value 4 bit command/data
*/
void write4bits(uint8_t value) {
	expanderWrite(value);
	pulseEnable(value);
}

/**  
* @brief LCD Display send i2c data
* @retval None
* @param _data data byte to send over i2c
*/
void expanderWrite(uint8_t _data){                                        
	I2C_MASTER_SEND_DATA(((int)(_data) | _backlightval),LCD_I2C_ADDR); 
}

/**  
* @brief LCD Display send enable pulse
* @retval None
* @param _data data byte to send over i2c
* @note refer timing diagram for 4 bit operations
*/
void pulseEnable(uint8_t _data){
	expanderWrite(_data | En);	// En high
	DELAY(1);		// enable pulse must be >450ns
	
	expanderWrite(_data & ~En);	// En low
	DELAY(50);		// commands need > 37us to settle
} 

/**  
* @brief LCD Display send characters
* @retval None
* @param str pointer to strings of character
*/
void send_string(char *str){
    int i = 0;
    while (str[i]!='\0')
    {
        /* send character code */
        lcd_write(str[i]);
        i++;
    }
    
}
