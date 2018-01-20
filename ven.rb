require 'sequel'
require 'date'
require './secrets'

class Ven

	def initiliaze
		@closing_price
		@closing_time
	end

	def save
		set_up_db
	end

	def create
		set_up_db
		@vens.insert(closing_price: 123, closing_time: 11113232, created_at: DateTime.now, updated_at: DateTime.now)
	end

	def set_up_db
		@db = Sequel.connect(adapter: 'mysql2', user: Secrets.database_username, 
							 password: Secrets.database_password, database: 'binance')


		@vens = @db[:vens]
	end

end