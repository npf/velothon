/*
 *  Velothon
 *  Copyright (C) 2008-2009 Pierre Neyron <pierre.neyron@free.fr>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

int inputPin[]={2,3,4,5,6,7,8,9,10,11};
unsigned long counter[]={0,0,0,0,0,0,0,0,0,0};
int state[]={LOW,LOW,LOW,LOW,LOW,LOW,LOW,LOW,LOW,LOW};
unsigned long time[]={0,0,0,0,0,0,0,0,0,0};

void setup() {
  int i=0;
  for (i=0;i<10;i++) {
  	pinMode(inputPin[i], INPUT);
  }
  Serial.begin(115200);
	Serial.println("Starting counter !!");
	delay(100);
}

void loop(){
  int i=0;
  unsigned long t;
  for (i=0;i<10;i++) {
    if (digitalRead(inputPin[i]) == HIGH) {
			state[i]=HIGH;
  	} else {
			if (state[i] == HIGH) {
				counter[i]++;
        time[i]=millis();	
				Serial.print(i);
				Serial.print("|");
				Serial.print(counter[i]);
        Serial.print("|");
        Serial.println(time[i]);
			}
			state[i]=LOW;
	  }
  }
}
