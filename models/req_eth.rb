require 'sequel'
require 'date'
require './secrets'

db = Sequel.connect(adapter: 'mysql2', user: Secrets.database_username, password: Secrets.database_password, database: 'binance')

class ReqEth < Sequel::Model(db[:reqs])

end