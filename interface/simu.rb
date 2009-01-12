#!/usr/bin/ruby
#
#  Velothon
#  Copyright (C) 2008-2009 Pierre Neyron <pierre.neyron@free.fr>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
require 'gtk2'

bikes = Array.new(10) {|i|
	Gtk::ToggleButton.new("#{i}")
}
window = Gtk::Window.new
hbox = Gtk::HBox.new
window.add(hbox)
bikes.each do |b|
	hbox.pack_start(b)
end
window.show_all

Thread.new do
	Gtk.main
end

counters = Array.new(10) { 0 }
File.open("/tmp/ttyUSB0","w") do |fd|
	while true do
		#sleep(rand() / 100)
		#counter = rand(10)
		sleep(0.189)
		0.upto(9) do |counter|
			if bikes[counter].active?
				fd.puts "#{counter}: #{counters[counter]}" 
#				puts "#{counter}: #{counters[counter]}" 
				counters[counter] += 1
				fd.flush
			end
		end
	end
end
puts "Bybye"
