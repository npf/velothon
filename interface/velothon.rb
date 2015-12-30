#!/usr/bin/ruby -w
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
require 'thread'
Thread::abort_on_exception=true
require 'eregex'
require 'observer'
require 'gtk2'
require 'singleton'
require 'gnomecanvas2'
#LCD_FONT = 'LCD Bold'
LCD_FONT = 'Sans'

class Tick
	attr_reader :index, :value, :time
	#@@TTY = "/tmp/ttyUSB0"
	@@TTY = "/dev/ttyS0"
	def initialize(index, value, time)
		@index = index
		@value = value
		@time = time.to_f/1000
	end
	def to_s
		"#{@index}:#{@value}:#{@time}"	
	end
	def -(tick)
		[ self.time - tick.time , self.value - tick.value ]
	end
	def Tick.poll
		thread = Thread.new do
			regex = Regexp.new('^(\d+)\|(\d+)\|(\d+)')
			input = File.new(@@TTY)
			input.each_line do |line|
				if match = regex.match(line)	
					tick = Tick.new(match[1].to_i,match[2].to_i,match[3].to_i)
					yield tick
				end
			end
			input.close			
		end 
		return thread
	end
end

class Fixnum
	def to_dist(wheel)
		self * wheel
	end
end

class Bike
	include Observable
	attr_reader :no, :desc, :wheel, :team
	attr_reader :time, :dist, :speed, :maxspeed
	attr_reader :ol_time, :ol_dist, :ol_maxspeed
## class attributes and methods
	@@auto_refresh = false
	@@bikes = nil
	@@observers = Array.new
	@@rate = 120
	def self.bikes
		return @@bikes
	end
	def self.reg_observer(observer)
		@@observers.push(observer)
	end
	def self.create(bikes)
		@@bikes = Array.new(bikes.size) do |i|
			bikes[i].default = 0
			bike = Bike.new(bikes[i][:no], bikes[i][:desc], bikes[i][:wheel], bikes[i][:ol_time], bikes[i][:ol_dist], bikes[i][:ol_maxspeed])
			@@observers.each do |observer|
				bike.add_observer(observer)
			end	
			bike
		end
 	end
	def self.rate
		@@rate
	end
	def self.rate=(rate)
		@@rate = rate
	end
## instance methods
	def initialize(no, desc, wheel=2.10, ol_time=0, ol_dist=0, ol_maxspeed=0)
		@no = no
		@desc = desc
		@wheel = wheel
		@stopped = false
		@lasttick = nil
		@time = 0
		@dist = 0
		@speed = 0
		@maxspeed = 0
		@ol_time = ol_time
		@ol_dist = ol_dist
		@ol_maxspeed = ol_maxspeed
		@team = nil
		@stop_time = Time.new
	end
	def to_s
		return <<EOS
Bike: { :no=>#{@no}, :desc=>"#{desc}", :wheel=>#{wheel}, :ol_time=>#{@ol_time}, :ol_dist=>#{@ol_dist}, :ol_maxspeed=>#{@ol_maxspeed} }
EOS
	end
	def start(team, duration)
		if team.credit * @@rate >= duration
			@team = team
			@team.use_credit(duration/@@rate)
			@stop_time = Time.new + duration
			@time = 0
			@dist = 0
			@maxspeed = 0
			return true
		end
		return false
	end
	def stop
		team.unuse_credit(((@stop_time - Time.new) / @@rate).floor)
		@stop_time = Time.new
		return true
	end
	def running
		return Time.new < @stop_time	
	end
	def eta
		if running
		 		return @stop_time - Time.new
			else
				return 0
		end
	end
	def avgspeed
		if @time > 0
			return @dist / @time
		else
			return 0
		end
	end
	def ol_avgspeed
		if @ol_time > 0
			return @ol_dist / @ol_time
		else
			return 0
		end
	end
	def refresh(force = false)
		changed
		if (@@auto_refresh or force)
			notify_observers(self)
		end
	end
	def add_observer(observer)
		super
		refresh(true)
	end
	def update(time, dist, speed)
		@ol_time += time
		@ol_dist += dist
		#@speed_array.push(speed)
		#while @speed_array.size > @speed_samples
		#	@speed_array.shift
		#end
		#if @speed_array.size == @speed_samples
		#	@speed = @speed_array.inject(0) {|sum, s| sum + s} / @speed_array.size
		#	puts "[#{@speed_array.join(", ")}] / #{@speed_array.size} = #{@speed * 3.6}"
		#else
		#	@speed = 0
		#end
		@speed = speed
		if @speed > @ol_maxspeed
			@ol_maxspeed = @speed
		end
		if running
			@time += time
			@dist += dist
			if @speed > @maxspeed
				@maxspeed = @speed
			end
			@team.update(time, dist, speed)
		end
		refresh
	end
	def tock(tick)
		if @lasttick.nil?
			@lasttick = tick
		else
			if tick.value > @lasttick.value + 1
				warn "lost a tick (#{tick.value} > #{@lasttick.value})"
			end
			(time_delta, tick_delta) = tick - @lasttick
			dist_delta = tick_delta.to_dist(@wheel)
			speed = dist_delta / time_delta
			update(time_delta, dist_delta, speed)
			@lasttick = tick
		end	
	end
end

class Team
	include Observable
	attr_reader :name, :credit, :ol_credit
	attr_reader :time, :dist, :maxspeed
## class attributes and methods
	@@auto_refresh = false
	@@teams = Hash.new
	@@observers = Array.new
	@@first = nil
	@@last = nil
	def self.teams
		return @@teams
	end
	def self.reg_observer(observer)
		@@observers.push(observer)
	end
	def self.create(name, credit = 0, ol_credit = 0, time = 0, dist = 0, maxspeed = 0)
		if @@teams.has_key?(name)
			raise "team already exists"
		end
		@@teams[name] = Team.new(name, credit, ol_credit, time, dist, maxspeed)
		if @@first.nil?
			@@first = @@teams[name]
		end
		if @@last.nil?
			@@last = @@teams[name]
		end
		@@observers.each do |observer|
			@@teams[name].add_observer(observer)
		end
		@@teams[name]
	end
	def self.first
		if @@first.nil?
			raise "no team"
		end
		return @@first
	end
	def self.last
		if @@last.nil?
			raise "no team"
		end
		@@teams.each_value do |team|	
			if @@last.dist > team.dist
				@@last = team	
			end 
		end
		return @@last
	end
## instance methods
	def initialize(name, credit, ol_credit, time, dist, maxspeed)
		@name = name
		@credit = credit
		@ol_credit = ol_credit
		@time = time
		@dist = dist
		@maxspeed = maxspeed
		@bikes = Array.new
	end
	def avgspeed
		if @time > 0
			return @dist / @time
		else
			return 0
		end
	end
	def refresh(force = false)
		changed
		if (@@auto_refresh or force)
			notify_observers(self)
		end
	end
	def add_observer(observer)
		super
		refresh(true)
	end
	def to_s
		return <<EOS
Team:("#{@name}", #{@credit}, #{@ol_credit}, #{@time}, #{@dist}, #{@maxspeed})
EOS
	end
	def add_credit(credit) 
		@ol_credit += credit
		@credit += credit
		refresh
	end
	def cancel_credit(credit) 
		@ol_credit -= credit
		@credit -= credit
		refresh
	end
	def use_credit(credit) 
		@credit -= credit
		refresh
	end
	def unuse_credit(credit) 
		@credit += credit
		refresh
	end
	def update(time, dist, speed)
		@time += time
		@dist += dist
		if @dist > @@first.dist
			@@first = self
		end
		if speed > @maxspeed
			@maxspeed = speed
		end
		refresh
	end
	def bikes
		bikes = Array.new
		Bike.bikes.each do |b|
			if b.running and b.team == self
				bikes.push(b)
			end
		end
		bikes	
	end
end

class BikeDataStore < Gtk::ListStore
	def initialize
		super(Integer, String, Float, Float, Float, Float, Float, Float, Float, Float, Float, String)
		@bikes = Array.new(10) do |i|
			iter = self.append
			iter[0] = i + 1
			iter[1] = ""
			iter[2] = 0
			iter[3] = 0
			iter[4] = 0
			iter[5] = 0
			iter[6] = 0
			iter[7] = 0
			iter[8] = 0
			iter[9] = 0
			iter[10] = 0
			iter[11] = ""
			iter
		end
	end

	def update(bike)
		if bike.kind_of? Bike
			iter = @bikes[bike.no]
			iter[1] = bike.desc
			iter[2] = bike.wheel
			iter[3] = bike.time
			iter[4] = bike.dist / 1000
			iter[5] = bike.speed * 3600 / 1000
			iter[6] = bike.avgspeed * 3600 / 1000
			iter[7] = bike.maxspeed * 3600 / 1000
			iter[8] = bike.ol_dist / 1000
			iter[9] = bike.ol_avgspeed * 3600 / 1000	
			iter[10] = bike.ol_maxspeed	* 3600 / 1000
			iter[11] = if bike.running and not bike.team.nil?
					bike.team.name
				else
					""
				end
		else
			raise "Observable is not a Bike"	
		end
	end
end

class TeamDataStore < Gtk::ListStore
	def initialize
		super(Object, String, Float, Float, Float, Float, Float, Float, Float, String, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float)
		@iters = Hash.new
	end
	def update(team)
		if team.kind_of? Team
			unless @iters.has_key?(team) 
				iter = self.append
				@iters[team] = iter
				iter[0] = team
			end
			iter = @iters[team]
			iter[1] = team.name	
			iter[2] = team.time
			iter[3] = team.dist	/ 1000
			iter[4] = (team.bikes.inject(0) {|sum, b| sum + b.speed}) * 3600 / 1000
			iter[5] = team.avgspeed	* 3600 / 1000
			iter[6] = team.maxspeed	* 3600 / 1000
			iter[7] = team.ol_credit
			iter[8] = team.credit
			iter[9] = (team.bikes.collect {|b| b.no }).join(", ")

			l = 1000
			w = 500
			xg = 100
			xd = xg + w
			p = if Team.last.dist == [ Team.first.dist, l ].max
					1
				else 
					(team.dist - Team.last.dist) / ([ Team.first.dist, l ].max - Team.last.dist)
				end
			dg = [ 0, team.dist - l * p ].max
			dd = team.dist + l * (1 - p)
			db = (dg/l).ceil * l
			xv = xg + w * p 
			xb = (db - dg) / l * w + xg
			iter[10] = p
			iter[11] = l
			iter[12] = dg 
			iter[13] = dd
			iter[14] = db
			iter[15] = w
			iter[16] = xg 
			iter[17] = xd
			iter[18] = xv 
			iter[19] = xb 
		else
			raise "Observable is not a Team"	
		end
	end
	def team(iter)
		return @teams[iter]
	end
end

class BikeMonitor < Gtk::TreeView
	def initialize(bikestore, teamstore)
		super(bikestore)
		selection.mode = Gtk::SELECTION_NONE
		append_column(Gtk::TreeViewColumn.new("#", Gtk::CellRendererText.new, :text => 0))
		append_column(Gtk::TreeViewColumn.new("Description", Gtk::CellRendererText.new, :text => 1))
		append_column(Gtk::TreeViewColumn.new("Roue", Gtk::CellRendererText.new, :text => 2))
		append_column(Gtk::TreeViewColumn.new("Moyenne velo", Gtk::CellRendererText.new, :text => 9))
		append_column(Gtk::TreeViewColumn.new("Pointe velo", Gtk::CellRendererText.new, :text => 10))
		append_column(Gtk::TreeViewColumn.new("Distance velo", Gtk::CellRendererText.new, :text => 8))
		append_column(Gtk::TreeViewColumn.new("Vitesse", Gtk::CellRendererText.new, :text => 5))
		append_column(Gtk::TreeViewColumn.new("Temps", Gtk::CellRendererText.new, :text => 3))
		append_column(Gtk::TreeViewColumn.new("Distance", Gtk::CellRendererText.new, :text => 4))
		append_column(Gtk::TreeViewColumn.new("Moyenne", Gtk::CellRendererText.new, :text => 6))
		append_column(Gtk::TreeViewColumn.new("Pointe", Gtk::CellRendererText.new, :text => 7))
		append_column(Gtk::TreeViewColumn.new("Equipe", Gtk::CellRendererText.new, :text => 11))
	end
end

class TeamMonitor < Gtk::TreeView
	def initialize(teamstore)
		super
		selection.mode = Gtk::SELECTION_NONE
		append_column(Gtk::TreeViewColumn.new("Nom", Gtk::CellRendererText.new, :text => 1))
		append_column(Gtk::TreeViewColumn.new("Temps", Gtk::CellRendererText.new, :text => 2))
		append_column(Gtk::TreeViewColumn.new("Distance", Gtk::CellRendererText.new, :text => 3))
		append_column(Gtk::TreeViewColumn.new("Dons Total", Gtk::CellRendererText.new, :text => 7))
		append_column(Gtk::TreeViewColumn.new("Credits", Gtk::CellRendererText.new, :text => 8))
		append_column(Gtk::TreeViewColumn.new("Velos", Gtk::CellRendererText.new, :text => 9))
		append_column(Gtk::TreeViewColumn.new("p", Gtk::CellRendererText.new, :text => 10))
		append_column(Gtk::TreeViewColumn.new("l", Gtk::CellRendererText.new, :text => 11))
		append_column(Gtk::TreeViewColumn.new("dg", Gtk::CellRendererText.new, :text => 12))
		append_column(Gtk::TreeViewColumn.new("dd", Gtk::CellRendererText.new, :text => 13))
		append_column(Gtk::TreeViewColumn.new("db", Gtk::CellRendererText.new, :text => 14))
		append_column(Gtk::TreeViewColumn.new("w", Gtk::CellRendererText.new, :text => 15))
		append_column(Gtk::TreeViewColumn.new("xg", Gtk::CellRendererText.new, :text => 16))
		append_column(Gtk::TreeViewColumn.new("xd", Gtk::CellRendererText.new, :text => 17))
		append_column(Gtk::TreeViewColumn.new("xv", Gtk::CellRendererText.new, :text => 18))
		append_column(Gtk::TreeViewColumn.new("xb", Gtk::CellRendererText.new, :text => 19))
	end
end

class MonitorWindow < Gtk::Window
	def initialize(bikedatastore, teamdatastore) 
		super(Gtk::Window::TOPLEVEL)
		signal_connect("delete_event") {
		  true
		}
		vbox = Gtk::VBox.new(false, 10)
		add(vbox)
		bikesframe = Gtk::Frame.new("Bikes")
		teamsframe = Gtk::Frame.new("Teams")
		bikesframe.add(BikeMonitor.new(bikedatastore, teamdatastore))
		teamsframe.add(TeamMonitor.new(teamdatastore))
		vbox.add(bikesframe)
		vbox.add(teamsframe)
		show_all
	end
end

class ControlWindow < Gtk::Window
	def initialize(bikes, teamdatastore) 
		super(Gtk::Window::TOPLEVEL)
		signal_connect("delete_event") {
			true
		}
		hpaned = Gtk::HPaned.new
		add(hpaned)
		sponsorframe = Gtk::Frame.new()
		sponsorframe.add(SponsorControl.new(teamdatastore))
		hpaned.pack1(sponsorframe, false, false)
		bikeframe = Gtk::Frame.new()
		hpaned.pack2(bikeframe, false, false)
		notebook = Gtk::Notebook.new
		bikeframe.add(notebook)
		notebook.tab_pos = Gtk::POS_LEFT
		bikes.each do |b|
			bikecontrol = BikeControl.new(b, teamdatastore)
			notebook.append_page(bikecontrol, bikecontrol.label)
		end
		show_all
	end
end

class BikeControl < Gtk::VBox
	attr_reader :label
  def initialize(bike, teamstore)
		super(false)

		@label = Gtk::Label.new("#{bike.desc} (#{bike.eta.round})")

		pack_start(Gtk::Label.new("#{bike.desc} (\##{bike.no})"), false) 
		pack_start(Gtk::HSeparator.new, false)

		team_hbox = Gtk::HBox.new
		@team_label = Gtk::Label.new("Equipe:")
		@team_select = Gtk::TreeView.new(teamstore)
		@team_select.selection.mode = Gtk::SELECTION_BROWSE
		@team_select.headers_visible = false
		@team_select.append_column(Gtk::TreeViewColumn.new("Name", Gtk::CellRendererText.new, :text => 1))
		team_hbox.pack_start(@team_label)
		team_hbox.pack_end(@team_select)
		pack_start(team_hbox, true)

		duration_hbox = Gtk::HBox.new
		@duration_label = Gtk::Label.new("Duree (min):")
		@duration_select = Gtk::SpinButton.new(2,30,2)
		duration_hbox.pack_start(@duration_label)		
		duration_hbox.pack_end(@duration_select)		
		pack_start(duration_hbox, false)
	
		@start_button = Gtk::Button.new("Demarrer")
		@stop_button = Gtk::Button.new("Arreter")
		pack_end(@stop_button, false)
		pack_end(@start_button, false)
		
		@stop_button.sensitive = false
		@start_button.signal_connect('clicked') do
			iter = @team_select.selection.selected
			if iter.nil?
				dialog("Il faut selectionner une equipe")
			else
				team = iter[0]
				if bike.start(team, @duration_select.value * 60)
					update(bike)
				else
					dialog("Plus de sponsor !")
				end
			end
		end 
		@stop_button.signal_connect('clicked') do
			bike.stop()
			update(bike)
		end 
		show_all
		bike.add_observer(self)
	end

	def update(bike)
		if bike.kind_of? Bike
			if bike.running 
				@team_label.sensitive = false
				@team_select.sensitive = false
				@duration_label.sensitive = false	
				@duration_select.sensitive = false	
				@start_button.sensitive = false
				@stop_button.sensitive = true
			else
				@team_label.sensitive = true
				@team_select.sensitive = true
				@duration_label.sensitive = true	
				@duration_select.sensitive = true	
				@start_button.sensitive = true
				@stop_button.sensitive = false
			end
			@label.text = "#{bike.desc} (#{bike.eta.round})"
		else
			raise "Observable is not a Team"
		end
	end
	def dialog(msg)
    d = Gtk::MessageDialog.new(self.toplevel, Gtk::Dialog::DESTROY_WITH_PARENT, Gtk::MessageDialog::ERROR, Gtk::MessageDialog::BUTTONS_CLOSE, msg)
    d.run
		d.destroy
	end
end

class SponsorControl < Gtk::VBox
  def initialize(teamstore)
    super()

		pack_start(Gtk::Label.new("Dons"), false) 
		pack_start(Gtk::HSeparator.new, false)

		rate_hbox = Gtk::HBox.new
		rate_label = Gtk::Label.new("Rapport (min/euros):")
		rate_select = Gtk::SpinButton.new(1,10,1)
		rate_select.value=2
		rate_button = Gtk::Button.new("Ok")
		rate_hbox.pack_start(rate_label)
		rate_hbox.pack_end(rate_button)
		rate_hbox.pack_end(rate_select)
		pack_start(rate_hbox, false)
		rate_button.signal_connect('clicked') do
			Bike.rate = (rate_select.value * 60).to_i
		end 

		team_hbox = Gtk::HBox.new
		team_label = Gtk::Label.new("Equipe:")
		team_select = Gtk::TreeView.new(teamstore)
		team_select.selection.mode = Gtk::SELECTION_BROWSE
		team_select.headers_visible = false
		team_select.append_column(Gtk::TreeViewColumn.new("Name", Gtk::CellRendererText.new, :text => 1))
		team_hbox.pack_start(team_label)
		team_hbox.pack_end(team_select)
		pack_start(team_hbox, true)

		amount_hbox = Gtk::HBox.new
		amount_label = Gtk::Label.new("Somme (euros):")
		amount_select = Gtk::SpinButton.new(1,100,1)
		amount_hbox.pack_start(amount_label)
		amount_hbox.pack_end(amount_select)
		pack_start(amount_hbox, false)

		pay_button = Gtk::Button.new("Encaisser")
		pack_end(pay_button, false)

		pay_button.signal_connect('clicked') do
			iter = team_select.selection.selected
			unless iter.nil?
				team = iter[0]
				team.add_credit(amount_select.value)
			end
		end 
		show_all
	end
end

class RoadDisplayWindow < Gtk::Window
	def initialize()
		super(Gtk::Window::TOPLEVEL)
		signal_connect("delete_event") {
		  true
		}
		@roads = Hash.new
		@vbox = Gtk::VBox.new
		add(@vbox)
		show_all
	end
	def update(team)
		if team.kind_of? Team
			unless @roads.has_key?(team) 
				@roads[team] = TeamRoad.new
				@vbox.pack_start(@roads[team])
			end
			@roads[team].update(team)
		end
	end
end

class BikeDisplayWindow < Gtk::Window
	def initialize()
		super(Gtk::Window::TOPLEVEL)
		signal_connect("delete_event") {
		  true
		}
		@hbox = Gtk::HBox.new
		add(@hbox)
		Bike.bikes.each do |bike|
			@hbox.pack_start(BikeStats.new(bike))
		end
		show_all
	end
end

class RoadBikeDisplayWindow < Gtk::Window
	def initialize()
		super(Gtk::Window::TOPLEVEL)
		signal_connect("delete_event") {
		  true
		}
		vpaned = Gtk::VPaned.new
		add(vpaned)
		@roads = Hash.new
		@vbox = Gtk::VBox.new
		vpaned.pack1(@vbox, false, false)
		@hbox = Gtk::HBox.new
		vpaned.pack2(@hbox, false, false)
		Bike.bikes.each do |bike|
			@hbox.pack_start(BikeStats.new(bike))
		end
		show_all
	end
	def update(team)
		if team.kind_of? Team
			unless @roads.has_key?(team) 
				@roads[team] = TeamRoad.new
				@vbox.pack_start(@roads[team])
			end
			@roads[team].update(team)
		end
	end
end

class BikeStats < Gtk::VBox
	def initialize(bike)
		super()
		@label_name = Gtk::Label.new
		frame_name = Gtk::Frame.new("Velo")
		frame_name.add(@label_name)
		pack_start(frame_name)
		@label_team = Gtk::Label.new
		frame_team = Gtk::Frame.new("Equipe")
		frame_team.add(@label_team)
		frame_team.height_request = 80
		pack_start(frame_team)
		@label_time = Gtk::Label.new
		frame_time = Gtk::Frame.new("Temps\nrestant")
		frame_time.add(@label_time)
		pack_start(frame_time)
		@label_dist = Gtk::Label.new
		frame_dist = Gtk::Frame.new("Distance\nparcourue")
		frame_dist.add(@label_dist)
		pack_start(frame_dist)
		@label_speed = Gtk::Label.new
		frame_speed = Gtk::Frame.new("Vitesse\ninstantanee")
		frame_speed.add(@label_speed)
		pack_start(frame_speed)
		@label_avgspeed = Gtk::Label.new
		frame_avgspeed = Gtk::Frame.new("Vitesse\nmoyenne")
		frame_avgspeed.add(@label_avgspeed)
		pack_start(frame_avgspeed)
		@label_maxspeed = Gtk::Label.new
		frame_maxspeed = Gtk::Frame.new("Vitesse\nmaximum")
		frame_maxspeed.add(@label_maxspeed)
		pack_start(frame_maxspeed)
		show_all
		bike.add_observer(self)
	end
	def update(bike)
		if bike.kind_of? Bike
			@label_name.markup = "<span font_desc='Sans 16'>#{bike.desc}</span>"
			@label_team.markup = if bike.running and not bike.team.nil?
					"<span font_desc='Sans 16'>#{bike.team.name}</span>"
				else
					"<span font_desc='Sans 16' foreground='red'>libre</span>"
				end
			@label_time.markup = "<span font_desc='#{LCD_FONT} 24'>#{bike.eta.round}</span><span font_desc='Sans 10'> s</span>"
			@label_dist.markup =  "<span font_desc='#{LCD_FONT} 24'>#{format("%.3f", bike.dist / 1000)}</span><span font_desc='Sans 10'> Km</span>"
			@label_speed.markup = "<span font_desc='#{LCD_FONT} 24'>#{format("%.1f", bike.speed * 3600 / 1000)}</span><span font_desc='Sans 10'> Km/h</span>"
			@label_avgspeed.markup = "<span font_desc='#{LCD_FONT} 24'>#{format("%.1f", bike.avgspeed * 3600 / 1000)}</span><span font_desc='Sans 10'> Km/h</span>"
			@label_maxspeed.markup = "<span font_desc='#{LCD_FONT} 24'>#{format("%.1f", bike.maxspeed * 3600 / 1000)}</span><span font_desc='Sans 10'> Km/h</span>"
		else
			raise "observable is not a Team"
		end
	end
end

class TeamRoad < Gtk::HBox
	@@pixbuf_bike = [
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
		Gdk::Pixbuf.new("bike.png"),
	]
	@@pixbuf_background = Gdk::Pixbuf.new("background.png")
	def initialize()
		super()
		@dist_mile = 1000.0
		@dist_left = 0.0
		@dist_milestone = 0.0
		@pos = 0.0
		@x_pad = @@pixbuf_bike[0].width / 2
		@x_mile = 900
		@width = @x_mile + 2 * @x_pad
		@height = @@pixbuf_background.height
		@x_bike = @x_pad
		@x_milestone = @x_pad
		@x_background = @x_pad
		@y_bike = @height - @@pixbuf_bike[0].height / 2 - 5
		@y_milestone = @height / 2
		@y_background = @@pixbuf_background.height / 2

		frame_name = Gtk::Frame.new("Equipe")
		frame_name.label_xalign = 0
		frame_name.set_size_request(180, @height)
		pack_start(frame_name)
		@label_name = Gtk::Label.new
		@label_name.xalign = 0
		frame_name.add(@label_name)
		frame_credit = Gtk::Frame.new("Credits/Dons")
		pack_end(frame_credit)
		@label_credit = Gtk::Label.new
		frame_credit.add(@label_credit)
		frame_credit.set_size_request(120, @height)
		frame_dist = Gtk::Frame.new("Distance")
		pack_end(frame_dist)
		@label_dist = Gtk::Label.new
		frame_dist.add(@label_dist)
		frame_dist.set_size_request(100, @height)

		@box = Gtk::EventBox.new
		pack_end(@box)
		@box.set_size_request(@width, @height)
		@canvas = Gnome::Canvas.new(false)
		@box.add(@canvas)
		@canvas_background = Gnome::CanvasPixbuf.new(@canvas.root, {:pixbuf => @@pixbuf_background , :x => @x_background, :y => @y_background, :anchor => Gtk::ANCHOR_CENTER})
		@canvas_milestone0 = Gnome::CanvasText.new(@canvas.root, {:text => "#{(@dist_milestone/1000).round - 1}", :x => (@x_milestone - @x_mile), :y => @y_milestone, :anchor => Gtk::ANCHOR_CENTER, :fill_color => "black"})
		@canvas_milestone1 = Gnome::CanvasText.new(@canvas.root, {:text => "#{(@dist_milestone/1000).round}", :x => (@x_milestone), :y => @y_milestone, :anchor => Gtk::ANCHOR_CENTER, :fill_color => "black"})
		@canvas_milestone2 = Gnome::CanvasText.new(@canvas.root, {:text => "#{(@dist_milestone/1000).round + 1}", :x => (@x_milestone + @x_mile), :y => @y_milestone, :anchor => Gtk::ANCHOR_CENTER, :fill_color => "black"})
		@canvas_bike = Gnome::CanvasPixbuf.new(@canvas.root, {:pixbuf => @@pixbuf_bike[0], :x => @x_bike, :y => @y_bike, :anchor => Gtk::ANCHOR_CENTER})
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
	def update(team)
		if team.kind_of? Team
			@pos = if Team.last.dist == [ Team.first.dist, @dist_mile ].max
					1
				else 
					(team.dist - Team.last.dist) / ([ Team.first.dist, @dist_mile ].max - Team.last.dist)
				end
			@dist_left = [ 0, team.dist - @dist_mile * @pos ].max
			@dist_milestone = (@dist_left/@dist_mile).ceil * @dist_mile
			@x_bike = @pos * (@x_mile) + @x_pad
			@x_background = (@dist_milestone - @dist_left) / @dist_mile * (@x_mile) + @x_pad
			@x_milestone = (@dist_milestone - @dist_left) / @dist_mile * (@x_mile) + @x_pad
			@canvas_bike.x = @x_bike
			@canvas_bike.pixbuf = @@pixbuf_bike[team.bikes.size]
			@canvas_background.x = @x_background
			@canvas_milestone0.x = @x_milestone - @x_mile
			@canvas_milestone1.x = @x_milestone
			@canvas_milestone2.x = @x_milestone + @x_mile
			@canvas_milestone0.text = "#{(@dist_milestone/1000).round - 1}"
			@canvas_milestone1.text = "#{(@dist_milestone/1000).round}"
			@canvas_milestone2.text = "#{(@dist_milestone/1000).round + 1}"

			@label_dist.markup="<span font_desc='#{LCD_FONT} 24'>#{format("%.1f",team.dist/1000)}</span><span font_desc='Sans 10'> Km</span>"
			if team.credit == 0
				@label_credit.markup="<span font_desc='#{LCD_FONT} 24' foreground='red'>#{team.credit.round}</span><span font_desc='#{LCD_FONT} 14'>/#{team.ol_credit.round}</span><span font_desc='Sans 10'> euros</span>"
			else
				@label_credit.markup="<span font_desc='#{LCD_FONT} 24'>#{team.credit.round}</span><span font_desc='#{LCD_FONT} 14'>/#{team.ol_credit.round}</span><span font_desc='Sans 10'> euros</span>"
			end
			#@label_name.markup="<span font_desc='Comic Sans MS Bold 24'>#{team.name} </span>"
			@label_name.markup="<span font_desc='Sans 20'>#{team.name} </span>"
		else
			raise "observable is not a Team"
		end
	end
end

class Dumper
	def update(counter)
		puts counter
	end
end

###############################################################################
## Main
###############################################################################

#bikedatastore = BikeDataStore.new
teamdatastore = TeamDataStore.new
dumper = Dumper.new

#Bike.reg_observer(dumper)
Team.reg_observer(dumper)

#Bike.reg_observer(bikedatastore)
Team.reg_observer(teamdatastore)

Bike.create([
	{:no => 0, :desc => "Velo 1", :wheel => 2.10,},
	{:no => 1, :desc => "Velo 2", :wheel => 2.10 },
	{:no => 2, :desc => "Velo 3", :wheel => 2.10 },
	{:no => 3, :desc => "Velo 4", :wheel => 2.10 },
	{:no => 4, :desc => "Velo 5", :wheel => 2.10 },
	{:no => 5, :desc => "Velo 6", :wheel => 2.10 },
	{:no => 6, :desc => "Velo 7", :wheel => 2.10 },
	{:no => 7, :desc => "Velo 8", :wheel => 2.10 },
	{:no => 8, :desc => "Velo 9", :wheel => 2.10 },
	{:no => 9, :desc => "Velo 10", :wheel => 2.10 },
	])

#Bike.create([
#	{:no => 1, :desc => "Vélo 1", :wheel => 2.10 },
#	{:no => 0, :desc => "Vélo 2", :wheel => 2.10,},
#	{:no => 2, :desc => "Vélo 3", :wheel => 2.10 },
#	{:no => 6, :desc => "Vélo 4", :wheel => 2.10 },
#	{:no => 8, :desc => "Vélo 5", :wheel => 2.10 },
#	{:no => 7, :desc => "Vélo 6", :wheel => 2.10 },
#	{:no => 9, :desc => "Vélo 7", :wheel => 2.10 },
#	{:no => 3, :desc => "Vélo 8", :wheel => 2.10 },
#	{:no => 5, :desc => "Vélo 9", :wheel => 2.10 },
#	{:no => 4, :desc => "Vélo 10", :wheel => 2.10 },
#	])

index = [ 1, 0, 2, 6, 8, 7, 9, 3, 5, 4 ]
controlwindow = ControlWindow.new(Bike.bikes, teamdatastore)

#monitorwindow = MonitorWindow.new(bikedatastore, teamdatastore)

#bikewindow = BikeDisplayWindow.new
#displaywindow = RoadDisplayWindow.new
displaywindow = RoadBikeDisplayWindow.new

Team.reg_observer(displaywindow)

# Team("name",credit,ol_credit,time,dist,maxspeed)
Team.create("Arcisse\n")
Team.create("Chamont\n")
Team.create("La Biousse\n")
Team.create("Bourg Les Moles\nChamp-Benard")
Team.create("Le Rondeau\nVersin")
Team.create("Rivier Laval\nBonne-Gagne")
Team.create("Trieu\nCrucilleux")

refresh_delay = 0.5

gtk_thread = Thread.new do
	Gtk.main
end
poll_thread = Tick.poll do |tick|
	if tick.index >= 0 and tick.index <= 9
		Bike.bikes[tick.index].tock(tick)
	else
		warn "unknown tick index #{tick.index}"
	end
end
refresh_thread = Thread.new do
	while true
		Bike.bikes.each do |b|
			b.refresh(true)
		end
		Team.teams.each_pair do |n,t|
			t.refresh(true)
		end
		sleep refresh_delay
	end
end
gtk_thread.join
refresh_thread.join
poll_thread.join

