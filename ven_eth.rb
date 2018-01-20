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

	def save
	end

	def create!
		@vens.insert(opening_time: @opening_time, closing_price: @closing_price, closing_time: @closing_time, created_at: DateTime.now, updated_at: DateTime.now)
	end

end