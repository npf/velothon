#!/usr/bin/ruby -w

require "thread"
require 'eregex'
require 'gtk2'
require 'gnomecanvas2'
require 'yaml'
LCD_FONT = 'LCD Bold'

class Tick
	attr_reader :index, :value, :time
	@@TTY = "/tmp/ttyUSB0"
	#@@TTY = "/dev/ttyUSB0"
	@@QUEUE = Queue.new
	def initialize(index, value, time)
    @index = index
    @value = value
    @time = time
  end
	def -(tick)
		[ self.time - tick.time , self.value - tick.value ]
	end
	def Tick.queue
		@@QUEUE
	end
	def Tick.poll
		thread = Thread.new do
			regex = Regexp.new('^(\d+)\|(\d+)\|(\d+)')
			input = File.new(@@TTY)
			input.each_line do |line|
				if match = regex.match(line)	
					tick = Tick.new(match[1].to_i,match[2].to_i,match[3].to_i)
					@@QUEUE.push(tick)
				end
			end
			input.close			
		end 
		return thread
	end
	def Tick.test
		while true do
			begin
#				while (t = Tick.queue.pop(non_block=true)) do
				while (t = Tick.queue.pop) do
  				puts "pop #{t}"
				end
				rescue ThreadError
					puts "Tick queue is empty..."
				sleep 0.1
			end
		end
	end
  def to_s
    "#{@index}:#{@value}:#{@time}"
  end
end

class Bike
	attr_reader :index, :name, :wheel
	attr_reader :time, :dist, :speed, :max_speed
	attr_reader :time_cur, :dist_cur, :max_speed_cur
	@@BIKES = Hash.new
	@@FIRST = nil
	@@LAST = nil
	def initialize(index, name, wheel)
		@index = index
		@name = name
		@wheel = wheel
		@last_tick = nil
		@time = 0
		@dist = 0
		@speed = 0
		@max_speed = 0
		reset_cur
	end
	def reload(dist=0,time=0,max_speed=0)
		@dist = dist
		@time = time
		@max_speed = @max_speed
	end
	def reset_cur
		@time_cur = 0
		@dist_cur = 0
		@max_speed_cur = 0
	end
	def avg_speed
		if @time > 0
			return @dist / @time * 3600
		else
			return 0
		end
	end
	def avg_speed_cur
		if @time_cur > 0
			return @dist_cur / @time_cur * 3600
		else
			return 0
		end
	end
	def tock(tick)
		if @last_tick.nil?
			@last_tick = tick
		else
			if tick.value > @last_tick.value + 1
				warn "lost a tick (#{tick.value} > #{@last_tick.value})"
			end
			(time_delta, tick_delta) = tick - @last_tick
			dist_delta = tick_delta * @wheel
			@time += time_delta
			@time_cur += time_delta
			@dist += dist_delta
			if @dist > @@FIRST.dist
				@@FIRST = self
			end
			@dist_cur += dist_delta
			@speed = dist_delta / time_delta * 3600
			if @speed > @max_speed
				@max_speed = @speed
			end
			if @speed > @max_speed_cur
				@max_speed_cur = @speed
			end
			@last_tick = tick
			puts "Bike[#{@index}].reload(#{@dist}, #{@time}, #{@max_speed})"
		end
	end
	def self.create(index, name, wheel)
		bike = Bike.new(index, name, wheel)
		@@BIKES[index] = bike
		if @@FIRST.nil?
			@@FIRST=bike
		end
		if @@LAST.nil?
			@@LAST=bike
		end
	end
	def self.[](index)
		return @@BIKES[index]
	end
	def self.each()
		@@BIKES.sort.each do |i, b|
			yield i, b
		end 
	end
	def self.exist?(i)
		return @@BIKES.has_key?(i)
	end
	def self.first()
		if @@FIRST.nil?
			raise "First bike is not defined"
		end
		return @@FIRST
	end
	def self.last
		if @@LAST.nil?
			raise "Last bike is not defined"
		end
		@@BIKES.each_value do |b|
			if @@LAST.dist > b.dist
				@@LAST = b
			end
		end
		return @@LAST
	end
end

class Display < Gtk::Window
	def initialize()
		super(Gtk::Window::TOPLEVEL)
		signal_connect("delete_event") {
		  true
		}
		@vbox = Gtk::VBox.new
		add(@vbox)
		@refreshable = Array.new
		@do_refresh = false
		@refresh_thread = nil
		Bike.each do |i,b|
			road = Road.new(b)	
			@vbox.pack_start(road)
			@refreshable.push(road)
			stats = Stats.new(b)
			@vbox.pack_start(stats)
			@refreshable.push(stats)
		end
		show_all
	end
	def start_refresh(refresh_delay)
		@do_refresh = true
		@refresh_thread = Thread.new do
			while @do_refresh
				@refreshable.each do |r|
					r.refresh()
				end
				sleep(refresh_delay)
			end
		end
	end
	def stop_refresh()
		@do_refresh = false
		@refresh_thread.join()
	end
end

class Stats < Gtk::HBox
	def initialize(bike)
		super()
		@bike = bike
		@label = Gtk::Label.new
		pack_start(@label)
		@button = Gtk::Button.new
		pack_start(@button)
		@button.signal_connect('clicked') do
			@bike.reset_cur
		end
	end
	def refresh()
		@label.markup = "<span font_desc='Sans 11 Bold'>COUREUR:</span>" +
"<span font_desc='Sans 8'> temps:</span>" +
"<span font_desc='#{LCD_FONT} 11'>#{Time.at(@bike.time_cur/1000).utc.strftime('%T')}</span>" +
"<span font_desc='Sans 8'> - distance:</span>" +
"<span font_desc='#{LCD_FONT} 11'>#{format("%.3f", @bike.dist_cur / 1000)}</span>" +
"<span font_desc='Sans 8'>km - vitesse: </span> " +
"<span font_desc='#{LCD_FONT} 11'>#{format("%.1f", @bike.speed)}</span>" +
"<span font_desc='Sans 8'>km/h, moy: </span>" +
"<span font_desc='#{LCD_FONT} 11'>#{format("%.1f", @bike.avg_speed_cur)}</span>" +
"<span font_desc='Sans 8'>km/h, max: </span>" +
"<span font_desc='#{LCD_FONT} 11'>#{format("%.1f", @bike.max_speed_cur)}</span>" +
"<span font_desc='Sans 8'> - </span>" +
"<span font_desc='Sans 11 Bold'>TOTAL:</span>" +
"<span font_desc='Sans 8'> distance: </span>" +
"<span font_desc='#{LCD_FONT} 11'>#{format("%.3f", @bike.dist / 1000)}</span>" +
"<span font_desc='Sans 8'>km - vitesse moy: </span>" +
"<span font_desc='#{LCD_FONT} 11'>#{format("%.1f", @bike.avg_speed)}</span>" +
"<span font_desc='Sans 8'>km/h, max: </span>" +
"<span font_desc='#{LCD_FONT} 11'>#{format("%.1f", @bike.max_speed)}</span>" +
"<span font_desc='Sans 8'>km/h</span>"
	end
end

class Road < Gtk::HBox
	@@pixbuf_bike = [
		Gdk::Pixbuf.new("bike0.png"),
		Gdk::Pixbuf.new("bike1.png"),
		Gdk::Pixbuf.new("bike2.png"),
		Gdk::Pixbuf.new("bike3.png"),
		Gdk::Pixbuf.new("bike4.png"),
		Gdk::Pixbuf.new("bike5.png"),
		Gdk::Pixbuf.new("bike6.png"),
		Gdk::Pixbuf.new("bike7.png"),
		Gdk::Pixbuf.new("bike8.png"),
		Gdk::Pixbuf.new("bike9.png"),
	]
	@@pixbuf_background = Gdk::Pixbuf.new("background.png")
	def initialize(bike)
		super()
		@bike = bike
		@dist_mile = 1000.0
		@dist_left = 0.0
		@dist_milestone = 0.0
		@pos = 0.0
		@x_pad = @@pixbuf_bike[0].width / 2
		#@x_mile = 1302 #Screen 1366x768
		#@x_mile = 960 #Screen 1024x768
		@x_mile = 960
		@width = @x_mile + 2 * @x_pad
		@height = @@pixbuf_background.height
		@x_bike = @x_pad
		@x_milestone = @x_pad
		@x_background = @x_pad
		@y_bike = @height - @@pixbuf_bike[0].height / 2 - 5
		@y_milestone = @height / 2
		@y_background = @@pixbuf_background.height / 2

		@box = Gtk::EventBox.new
		pack_end(@box)
		@box.set_size_request(@width, @height)
		@canvas = Gnome::Canvas.new(false)
		@box.add(@canvas)
		@canvas_background = Gnome::CanvasPixbuf.new(@canvas.root, {:pixbuf => @@pixbuf_background , :x => @x_background, :y => @y_background, :anchor => Gtk::ANCHOR_CENTER})
		@canvas_bike_name = Gnome::CanvasText.new(@canvas.root, {:text => "#{@bike.name}", :x => 20, :y => 0, :anchor => Gtk::ANCHOR_NW, :fill_color => "dark red", :font => "Sans 20"})
		@canvas_dist = Gnome::CanvasText.new(@canvas.root, {:text => "0 km", :x => @x_mile, :y => 0, :anchor => Gtk::ANCHOR_NE, :fill_color => "dark red", :font => "Sans 20"})
		@canvas_milestone0 = Gnome::CanvasText.new(@canvas.root, {:text => "#{(@dist_milestone/1000).round - 1}", :x => (@x_milestone - @x_mile), :y => @y_milestone, :anchor => Gtk::ANCHOR_CENTER, :fill_color => "black"})
		@canvas_milestone1 = Gnome::CanvasText.new(@canvas.root, {:text => "#{(@dist_milestone/1000).round}", :x => (@x_milestone), :y => @y_milestone, :anchor => Gtk::ANCHOR_CENTER, :fill_color => "black"})
		@canvas_milestone2 = Gnome::CanvasText.new(@canvas.root, {:text => "#{(@dist_milestone/1000).round + 1}", :x => (@x_milestone + @x_mile), :y => @y_milestone, :anchor => Gtk::ANCHOR_CENTER, :fill_color => "black"})
		@canvas_bike = Gnome::CanvasPixbuf.new(@canvas.root, {:pixbuf => @@pixbuf_bike[@bike.index], :x => @x_bike, :y => @y_bike, :anchor => Gtk::ANCHOR_CENTER})
		@box.signal_connect('size-allocate') { |w,e,*b| 
		@width, @height = [e.width,e.height].collect{|i| i}
			@canvas.set_size(@width,@height)
			@canvas.set_scroll_region(0,0,@width,@height)
			false
		}
#		signal_connect_after('show') {|w,e| }
#		signal_connect_after('hide') {|w,e| }
		show_all()
	end
	def refresh()
		@pos = if Bike.last.dist == [ Bike.first.dist, @dist_mile ].max
					1
				else 
					(@bike.dist - Bike.last.dist) / ([ Bike.first.dist, @dist_mile ].max - Bike.last.dist)
				end
		@dist_left = [ 0, @bike.dist - @dist_mile * @pos ].max
		@dist_milestone = (@dist_left/@dist_mile).ceil * @dist_mile
		@x_bike = @pos * (@x_mile) + @x_pad
		@x_background = (@dist_milestone - @dist_left) / @dist_mile * (@x_mile) + @x_pad
		@x_milestone = (@dist_milestone - @dist_left) / @dist_mile * (@x_mile) + @x_pad
		@canvas_bike.x = @x_bike
		@canvas_dist.text = "#{format("%.3f",@bike.dist / 1000)} km"
		@canvas_background.x = @x_background
		@canvas_milestone0.x = @x_milestone - @x_mile
		@canvas_milestone1.x = @x_milestone
		@canvas_milestone2.x = @x_milestone + @x_mile
		@canvas_milestone0.text = "#{(@dist_milestone/1000).round - 1}"
		@canvas_milestone1.text = "#{(@dist_milestone/1000).round}"
		@canvas_milestone2.text = "#{(@dist_milestone/1000).round + 1}"
		#puts "[#{@bike.index}] pos=#{@pos} first=#{Bike.first.index} last=#{Bike.last.index} x_bike=#{@x_bike} x_background=#{@x_background} x_mikestone=#{@x_milestone}"
	end
end	

poll_thread = Tick.poll
#sleep 1
#Tick.test
gtk_thread = Thread.new do
	Gtk.main
end

Bike.create(0,"Montcarra",2.10)
Bike.create(1,"Salagnon",2.10)
Bike.create(2,"St Hilaire de Brens",2.10)
Bike.create(3,"St Marcel Bel Accueil",2.10)
Bike.create(4,"St Chef",2.10)
Bike.create(5,"Trept",2.10)
Bike.create(6,"Vénérieu",2.10)
Bike.create(7,"Vigneu",2.10)

#Bike[0].reload(1213.8, 57946, 0.021)
#Bike[1].reload(134.4, 6421, 0.021)

display = Display.new
display.start_refresh(0.5)

while true do
	begin
#		while (t = Tick.queue.pop(non_block=true)) do
		while (t = Tick.queue.pop) do
			if Bike.exist?(t.index)
				Bike[t.index].tock(t)
			end
		end
		rescue ThreadError
			puts "Tick queue is empty..."
		sleep 0.1
	end
end
display.stop_refresh()
poll_thread.join
gtk_thread.join
