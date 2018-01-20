require('binance')
require('indicators')
require('./secrets')

class BinanceBot
	def initialize
		if Secrets.api_key && Secrets.secret_key
			@client = Binance::Client::REST.new api_key: Secrets.api_key, secret_key: Secrets.secret_key
		else
			puts "NO API_KEY AND/OR SECRET_KEY FOUND"
			@client = Binance::Client::Rest.new
		end
	end

	def ping
		if !@client
			initialize_client
		end
		@client.ping
	end

	def klines(symbol, interval, limit=1)
		if !@client
			initialize_client
		end
		@client.klines symbol: symbol, interval: interval, limit: limit
	end

	def price_history(symbol, interval, limit=1)
		data = klines(symbol, interval, limit)
		data.map {|d| { open_time: d[0], close: d[4].to_f, close_time: d[5]} }
	end

	def public_products
		@client.products
	end

	def rsi_recently_crossed_threshold(rsiArray, index)
		tolerance = 10
		crossed = false
		rsiArray[(index - tolerance)..index].each do |rsi|
			if rsi > 70 || rsi < 30
				crossed = true
			end
		end
		crossed
	end
end





