require 'sequel'
require './secrets'
require 'binance'

class FunEthTradeModel

	attr_accessor :limit

	def initialize(signal: "buy", closing_price: 0.0, eth_amount: 0.0)
		@signal = signal
		@closing_price = closing_price.to_f
		@eth_amount = eth_amount.to_f
		@stop_price = closing_price.to_f
		if signal == "buy"
			@limit = closing_price.to_f * 0.95
		elsif signal == "sell"
			@limit = closing_price.to_f * 1.05
		end

		if Secrets.api_key && Secrets.secret_key
			@client = Binance::Client::REST.new api_key: Secrets.api_key, secret_key: Secrets.secret_key
		else
			puts "NO API_KEY AND/OR SECRET_KEY FOUND"
			@client = Binance::Client::REST.new
		end
	end

	def create_order(symbol, side, type, quantity)
		@client.create_order symbol: symbol, side: side, type: type, quantity: quantity
	end

	def update_price(new_price)
		if @signal == "buy"
			if new_price >= @stop_price
				puts "buying FUN"
			elsif new_price < @limit
				@stop_price = new_price
				@limit = new_price * 0.95
				puts "wait"
			else
				puts "wait"
			end
		elsif @signal == "sell"
			if new_price <= @stop_price
				puts "sell"
			elsif new_price > @limit
				@stop_price = new_price
				@limit = new_price * 1.05
				puts "wait"
			else
				puts "wait"
			end
		end
	end

end