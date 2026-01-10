/* @file  lcd_i2c.h
   @brief header file for operating 16x2 LCD with PCF8574 i2c expander
   @author Avinashee Tech
*/

#ifndef _LCD_I2c_H_
#define _LCD_I2C_H_

#include <stdint.h>

// commands
#define LCD_CLEARDISPLAY 0x01
#define LCD_RETURNHOME 0x02
#define LCD_ENTRYMODESET 0x04
#define LCD_DISPLAYCONTROL 0x08
#define LCD_CURSORSHIFT 0x10
#define LCD_FUNCTIONSET 0x20
#define LCD_SETCGRAMADDR 0x40
#define LCD_SETDDRAMADDR 0x80

// flags for display entry mode
#define LCD_ENTRYRIGHT 0x00
#define LCD_ENTRYLEFT 0x02
#define LCD_ENTRYSHIFTINCREMENT 0x01
#define LCD_ENTRYSHIFTDECREMENT 0x00

// flags for display on/off control
#define LCD_DISPLAYON 0x04
#define LCD_DISPLAYOFF 0x00
#define LCD_CURSORON 0x02
#define LCD_CURSOROFF 0x00
#define LCD_BLINKON 0x01
#define LCD_BLINKOFF 0x00

// flags for display/cursor shift
#define LCD_DISPLAYMOVE 0x08
#define LCD_CURSORMOVE 0x00
#define LCD_MOVERIGHT 0x04
#define LCD_MOVELEFT 0x00

// flags for function set
#define LCD_8BITMODE 0x10
#define LCD_4BITMODE 0x00
#define LCD_2LINE 0x08
#define LCD_1LINE 0x00
#define LCD_5x10DOTS 0x04
#define LCD_5x8DOTS 0x00

// backlight control
#define LCD_BACKLIGHT 0x08
#define LCD_NOBACKLIGHT 0x00

#define En 0x04  // Enable bit
#define Rw 0x02  // Read/Write bit
#define Rs 0x01  // Register select bit

//function declarations
void send_string(char *str);
void pulseEnable(uint8_t _data);
void expanderWrite(uint8_t _data);
void write4bits(uint8_t value);
void lcd_send(uint8_t value, uint8_t mode);

void command(uint8_t value);
void lcd_write(uint8_t value);

void createChar(uint8_t location, uint8_t *charmap);
void setCursor(uint8_t col, uint8_t row);
void display(void);
void noDisplay(void);
void backlight(void);
void noBacklight(void);
void home(void);
void clear(void);
void lcd_begin(uint8_t cols, uint8_t lines, uint8_t dotsize);
void lcd_init(uint8_t lcd_cols,uint8_t lcd_rows);

//platform dependent functions
void delay_us(int us);
void print_message(const char* msg);
void master_send_data(uint8_t data,uint8_t i2c_addr);
int i2c_init(void);

#endif