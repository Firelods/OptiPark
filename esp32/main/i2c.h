/* @file  i2c.h
   @brief header file for basic i2c level operations
   @author Avinashee Tech
*/

#ifndef _I2C_H_
#define _I2C_H_

#include "esp_err.h"



int i2c_init(void);
esp_err_t master_write_slave(uint8_t data,uint8_t i2c_addr);
void master_send_data(uint8_t data,uint8_t i2c_addr);

#endif
