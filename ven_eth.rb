require 'sequel'
require 'date'
require './secrets'

class VenEth

	attr_reader :closing_price, :closing_time

	def initialize(closing_price: '', closing_time: '', database: Sequel.mysql2)
		@closing_price = closing_price
		@closing_time = closing_time
		@vens = database[:vens]
	end

	def save
	end

	def create!
		@vens.insert(closing_price: @closing_price, closing_time: @closing_time, created_at: DateTime.now, updated_at: DateTime.now)
	end

end