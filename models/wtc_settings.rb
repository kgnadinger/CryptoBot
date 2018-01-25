require 'sequel'
require 'date'
require './secrets'

db = Sequel.connect(adapter: 'mysql2', user: Secrets.database_username, password: Secrets.database_password, database: 'binance')

class WtcSetting < Sequel::Model(db[:wtc_settings])

	def recently_bought?
		if self.recently_bought == 1
			true
		else
			false
		end
	end

end