require 'sequel'
require 'date'
require './secrets'

class VenEth

	attr_reader :closing_price, :closing_time

	def initialize(opening_time: 0, closing_price: 0, closing_time: 0, database: Sequel.mysql2)
		@opening_time = opening_time
		@closing_price = closing_price
		@closing_time = opening_time + closing_time
		@vens = database[:vens]
	end

	def save!
		row = @vens.where(opening_time: @opening_time)
		puts row.count
		if row.count == 1
			row.update(closing_price: @closing_price, closing_time: @closing_time)
		else
			self.create!
		end
	end

	def create!
		@vens.insert(opening_time: @opening_time, closing_price: @closing_price, closing_time: @closing_time, created_at: DateTime.now, updated_at: DateTime.now)
	end

	def self.find(id)
		connect_to_database
		@db[:vens].where(id: id).first
	end

	def self.find_by(params)
		self.connect_to_database
		row = @db[:vens].where(params).first
		puts row
		row
	end

	def self.connect_to_database
		@db = Sequel.connect(adapter: 'mysql2', user: Secrets.database_username, 
							 password: Secrets.database_password, database: 'binance')
	end

end