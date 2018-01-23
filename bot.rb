require('binance')
require('indicators')
require('./secrets')
require 'eventmachine'
require('./rsi_macd_algorithm')
require './mailer'

class BinanceBot
	def initialize
		if Secrets.api_key && Secrets.secret_key
			@client = Binance::Client::REST.new api_key: Secrets.api_key, secret_key: Secrets.secret_key
		else
			puts "NO API_KEY AND/OR SECRET_KEY FOUND"
			@client = Binance::Client::REST.new
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

	def kline_with_end_time(symbol, interval, limit=1, endTime)
		if !@client
			initialize_client
		end
		@client.klines symbol: symbol, interval: interval, limit: limit, endTime: endTime
	end

	def price_history(symbol, interval, limit=1)
		data = klines(symbol, interval, limit)
		data.map {|d| { open_time: d[0].to_i, close_price: d[4].to_f, close_time: (d[5].to_i + d[0].to_i) } }
	end

	def price_history_with_end_time(symbol, interval, limit=1, endTime)
		data = kline_with_end_time(symbol, interval, limit, endTime)
		data.map {|d| { open_time: d[0].to_i, close_price: d[4].to_f, close_time: (d[5].to_i + d[0].to_i) } }
	end

	def public_products
		@client.products
	end

	def create_test_order(symbol, side, type="MARKET", quantity)
		@client.create_test_order symbol: symbol, side: side, type: type, quantity: quantity
	end

	def create_order(symbol, side, type, quantity)
		@client.create_order symbol: symbol, side: side, type: type, quantity: quantity
	end

	def account_info
		@client.account_info()
	end

	def getAmount(symbol)
		balance = 0
		account_info["balances"].each do |b|
			if b["asset"] == symbol
				balance = b["free"]
			end
		end
		balance
	end

	def stream
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	raw_price_history = price_history("FUNETH", '5m', 500)
	  		raw_price_history.each do |raw_price|
				ven_eth = FunEth.where(opening_time: raw_price[:open_time])
				if ven_eth && ven_eth.first
					ven_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					ven_eth = FunEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					ven_eth.save
				end
			end
		  }
		  message = proc { |e| 
		  	hash = eval(e.data)
		  	if hash[:k][:x]
		  		puts hash
		  		fun_eth = FunEth.where(opening_time: hash[:k][:t])
		  		if fun_eth && fun_eth.first
		  			fun_eth.first.update(opening_time: hash[:k][:t], 
										 closing_price: hash[:k][:c], 
										 closing_time: hash[:k][:T],
										 updated_at: DateTime.now)
		  		else
		  			fun_eth = FunEth.new(opening_time: hash[:k][:t], 
										 closing_price: hash[:k][:c], 
										 closing_time: hash[:k][:T],
										 updated_at: DateTime.now,
										 created_at: DateTime.now)
		  			fun_eth.save
		  		end
		  		fun_history = FunEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  		price_history = fun_history.map { |f| f.closing_price }
		  		algorithm = RsiMacdAlgorithm.new rsiTolerance: 1, price_history: price_history
		  		signal = algorithm.analyze
		  		if signal == "buy"
		  			puts "****Buying****"
		  			if getAmount("ETH").to_f > 0
		  				create_order("FUNETH", "buy", "MARKET", 1)
		  				mailer = Mailer.new
						mailer.send_text(text: "Buying FUNETH")
		  			else
		  				puts "Out of ETH"
		  			end
		  		elsif signal == "sell"
		  			puts "****Selling****"
		  			if getAmount("FUN").to_f > 0
		  				create_order("FUNETH", "sell", "MARKET", 1)
		  				mailer.send_text(text: "Selling FUNETH")
		  			end
		  		else
		  			puts "****Waiting****"
		  		end

		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { puts 'closed' }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }

		  # Pass a symbol and event handler Hash to connect and process events
		  # client.agg_trade symbol: 'FUNETH', methods: methods
		  
		  # kline takes an additional named parameter
		  client.kline symbol: 'FUNETH', interval: '5m', methods: methods

		  # As well as partial_book_depth
		  # client.partial_book_depth symbol: 'XRPETH', level: '5', methods: methods

		  # # Create a custom stream
		  # client.single stream: { type: 'aggTrade', symbol: 'XRPETH'}, methods: methods

		  # # Create multiple streams in one call
		  # client.multi streams: [{ type: 'aggTrade', symbol: 'XRPETH' },
		  #                        { type: 'ticker', symbol: 'XRPETH' },
		  #                        { type: 'kline', symbol: 'XRPETH', interval: '1m'},
		  #                        { type: 'depth', symbol: 'XRPETH', level: '5'}],
		  #              methods: methods 
		end
	end
end





