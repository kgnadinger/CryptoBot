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

	def test_stream
		puts "Implimant test stream"
	end

	# main bot method for live trading
	def stream
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trading pairs, this occurs at the beginning of the stream
		  	raw_price_history = price_history("FUNETH", '5m', 500)
	  		raw_price_history.each do |raw_price|
				fun_eth = FunEth.where(opening_time: raw_price[:open_time])
				if fun_eth && fun_eth.first
					fun_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					fun_eth = FunEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					fun_eth.save
				end
			end
			trx_raw_price_history = price_history("TRXETH", '5m', 500)
	  		trx_raw_price_history.each do |raw_price|
				trx_eth = TrxEth.where(opening_time: raw_price[:open_time])
				if trx_eth && trx_eth.first
					trx_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					trx_eth = TrxEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					trx_eth.save
				end
			end
			ven_raw_price_history = price_history("VENETH", '5m', 500)
	  		ven_raw_price_history.each do |raw_price|
				ven_eth = VenEth.where(opening_time: raw_price[:open_time])
				if ven_eth && ven_eth.first
					ven_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					ven_eth = VenEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					ven_eth.save
				end
			end
			wtc_raw_price_history = price_history("WTCETH", '5m', 500)
			wtc_raw_price_history.each do |raw_price|
				wtc_eth = WtcEth.where(opening_time: raw_price[:open_time])
				if wtc_eth && wtc_eth.first
					wtc_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					wtc_eth = WtcEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					wtc_eth.save
				end
			end
		  }
		  message = proc { |e| 
		  	# Grab the latest data hash from binance
		  	hash = eval(e.data)[:data]
		  	# if the price is the closing price
		  	if hash[:k][:x]
		  		# log hash
		  		puts hash

		  		# initialize array
		  		price_history = []
		  		if hash[:s] == "FUNETH"
		  			puts "FUNETH"
		  			# add new FunEth to database
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
			  		# Grab last 500 FunEth prices
		  			fun_history = FunEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = fun_history.map { |f| f.closing_price }
		  		elsif hash[:s] == "TRXETH"
		  			puts "TRXETH"
		  			# add new TrxEth to database
			  		trx_eth = TrxEth.where(opening_time: hash[:k][:t])
			  		if trx_eth && trx_eth.first
			  			trx_eth.first.update(opening_time: hash[:k][:t], 
											 closing_price: hash[:k][:c], 
											 closing_time: hash[:k][:T],
											 updated_at: DateTime.now)
			  		else
			  			trx_eth = TrxEth.new(opening_time: hash[:k][:t], 
											 closing_price: hash[:k][:c], 
											 closing_time: hash[:k][:T],
											 updated_at: DateTime.now,
											 created_at: DateTime.now)
			  			trx_eth.save
			  		end
			  		# Grab last 500 TrxEth prices
		  			trx_history = TrxEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = trx_history.map { |f| f.closing_price }
		  		elsif hash[:s] == "VENETH"
		  			puts "VENETH"
		  			# add new VenEth to database
			  		ven_eth = VenEth.where(opening_time: hash[:k][:t])
			  		if ven_eth && ven_eth.first
			  			ven_eth.first.update(opening_time: hash[:k][:t], 
											 closing_price: hash[:k][:c], 
											 closing_time: hash[:k][:T],
											 updated_at: DateTime.now)
			  		else
			  			ven_eth = VenEth.new(opening_time: hash[:k][:t], 
											 closing_price: hash[:k][:c], 
											 closing_time: hash[:k][:T],
											 updated_at: DateTime.now,
											 created_at: DateTime.now)
			  			ven_eth.save
			  		end
			  		# Grab last 500 VenEth prices
		  			ven_history = VenEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = ven_history.map { |f| f.closing_price }
		  		elsif hash[:s] == "WTCETH"
		  			puts "WTCETH"
		  			# add new WtcEth to database
			  		wtc_eth = WtcEth.where(opening_time: hash[:k][:t])
			  		if wtc_eth && wtc_eth.first
			  			wtc_eth.first.update(opening_time: hash[:k][:t], 
											 closing_price: hash[:k][:c], 
											 closing_time: hash[:k][:T],
											 updated_at: DateTime.now)
			  		else
			  			wtc_eth = WtcEth.new(opening_time: hash[:k][:t], 
											 closing_price: hash[:k][:c], 
											 closing_time: hash[:k][:T],
											 updated_at: DateTime.now,
											 created_at: DateTime.now)
			  			wtc_eth.save
			  		end
			  		# Grab last 500 WtcEth prices
		  			wtc_history = WtcEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = wtc_history.map { |f| f.closing_price }
		  		end

		  		# Initialize algorithm
		  		algorithm = RsiMacdAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 32, sell_zone: 67
		  		signal = algorithm.analyze # buy, sell or wait
		  		if hash[:s] == "FUNETH"
			  		if signal == "buy"
			  			puts "****Buying FUNETH****"

			  			# make sure we have enough ETH to buy
			  			if getAmount("ETH").to_f > 0

			  				# create a buy order
			  				create_order("FUNETH", "buy", "MARKET", 50)

			  				# log to database that we bought and its price
			  				f = FunSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f)
			  				f.save

			  				# text to alert that we bought
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying FUNETH")
			  			else
			  				puts "Out of ETH"
			  			end

			  		# Check if last setting exists and that recently bought is true
			  		elsif !FunSetting.last.nil? && FunSetting.last.recently_bought?

			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > FunSetting.last.recently_bought_price * 1.13
				  			puts "***Selling To Keep Profit***"

				  			# check we have enough coin to sell
				  			fun_amount = (getAmount("FUN").to_f * 0.25).ceil
				  			if fun > 0

				  				# sell
				  				create_order("FUNETH", "sell", "MARKET", fun_amount)

				  				# update setting
				  				FunSetting.last.update(recently_bought: false)

				  				# text to alert that we sold
				  				mailer = Mailer.new
				  				mailer.send_text(text: "Selling FUNETH")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling****"

			  			# check we have enough coin to sell
			  			fun_amount = (getAmount("FUN").to_f * 0.25).ceil
				  		if fun > 0

			  				# sell
			  				create_order("FUNETH", "sell", "MARKET", fun_amount)

			  				# update setting
			  				FunSetting.last.update(recently_bought: false)

			  				# text to alert that we sold
			  				mailer = Mailer.new
			  				mailer.send_text(text: "Selling FUNETH")
			  			end
			  		else
			  			puts "****Waiting****"
			  		end
			  	elsif hash[:s] == "TRXETH"
			  		if signal == "buy"
			  			puts "****Buying****"

			  			# make sure we have enough ETH to buy
			  			eth_amount = getAmount("ETH").to_f
			  			if eth_amount > 0

			  				# create a buy order
			  				create_order("TRXETH", "buy", "MARKET", 50)

			  				# log to database that we bought and its price
			  				f = TrxSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f)
			  				f.save

			  				# text to alert that we bought
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying TRXETH")
			  			else
			  				puts "Out of ETH"
			  			end

			  		# Check if last setting exists and that recently bought is true
			  		elsif !TrxSetting.last.nil? && TrxSetting.last.recently_bought?

			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > TrxSetting.last.recently_bought_price * 1.19
				  			puts "***Selling TRX To Keep Profit***"

				  			# check we have enough coin to sell
				  			trx_amount = (getAmount("TRX").to_f * 0.25).ceil
				  			if trx_amount > 0

				  				# sell
				  				create_order("TRXETH", "sell", "MARKET", trx_amount)

				  				# update setting
				  				TrxSetting.last.update(recently_bought: false)

				  				# text to alert that we sold
				  				mailer = Mailer.new
				  				mailer.send_text(text: "Selling TRXETH")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling****"
			  			trx_amount = (getAmount("TRX").to_f * 0.25).ceil
			  			if trx_amount > 0

			  				# sell
			  				create_order("TRXETH", "sell", "MARKET", trx_amount)

			  				# update settings
			  				TrxSetting.last.update(recently_bought: false)

			  				# text to alert that we sold
			  				mailer = Mailer.new
			  				mailer.send_text(text: "Selling TRXETH")
			  			end
			  		else
			  			puts "****Waiting****"
			  		end
			  	elsif hash[:s] == "VENETH"
			  		if signal == "buy"
			  			puts "****Buying VEN****"

			  			# make sure we have enough ETH to buy
			  			eth_amount = (getAmount("ETH").to_f * 0.01)
			  			if eth_amount > 0

			  				# create a buy order
			  				create_order("VENETH", "buy", "MARKET", 1)

			  				# log to database that we bought and its price
			  				f = VenSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f)
			  				f.save

			  				# text to alert that we bought
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying VENETH")
			  			else
			  				puts "Out of ETH"
			  			end

			  		# Check if last setting exists and that recently bought is true
			  		elsif !VenSetting.last.nil? && VenSetting.last.recently_bought?

			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > VenSetting.last.recently_bought_price * 1.3
				  			puts "***Selling VEN To Keep Profit***"

				  			# check we have enough coin to sell
				  			if getAmount("VEN").to_f > 0
				  				# we are not selling VEN as we expect it to rise substantially
				  				# create_order("VENETH", "sell", "MARKET", 2)

				  				# update settings
				  				VenSetting.last.update(recently_bought: false)

				  				# text to alert that we sold
				  				mailer = Mailer.new
				  				mailer.send_text(text: "Sell your VENETH to maximize profts -- manual sell only")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling VEN****"

			  			# check we have enough coin to sell
			  			if getAmount("VEN").to_f > 0
			  				# create_order("VENETH", "sell", "MARKET", 2)
			  				VenSetting.last.update(recently_bought: false)

			  				# text to alert that we sold
			  				mailer = Mailer.new
			  				mailer.send_text(text: "Sell your VENETH to maximize profts -- manual sell only")
			  			end
			  		else
			  			puts "****Waiting****"
			  		end
			  	elsif hash[:s] == "WTCETH"
			  		if signal == "buy"
			  			puts "****Buying WTC****"

			  			# make sure we have enough ETH to buy
			  			eth_amount = getAmount("ETH").to_f * 0.01
			  			if eth_amount > 0

			  				wtc_amount = eth_amount / hash[:k][:c].to_f
			  				# create a buy order
			  				create_order("WTCETH", "buy", "MARKET", wtc_amount)

			  				# log to database that we bought and its price
			  				f = WtcSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f)
			  				f.save

			  				# text to alert that we bought
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying WTCETH")
			  			else
			  				puts "Out of ETH"
			  			end

			  		# Check if last setting exists and that recently bought is true
			  		elsif !WtcSetting.last.nil? && WtcSetting.last.recently_bought?

			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > WtcSetting.last.recently_bought_price * 1.13
				  			puts "***Selling WTC To Keep Profit***"

				  			# check we have enough coin to sell
				  			wtc_amount = getAmount("WTC").to_f * 0.25
				  			if wtc_amount > 0

				  				# sell
				  				create_order("WTCETH", "sell", "MARKET", wtc_amount)

				  				# update setting
				  				WtcSetting.last.update(recently_bought: false)

				  				# text to alert that we sold
				  				mailer = Mailer.new
				  				mailer.send_text(text: "Selling WTCETH")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling WTC****"

			  			# check we have enough coin to sell
			  			wtc_amount = getAmount("WTC").to_f * 0.25
				  		if wtc_amount > 0
			  				create_order("WTCETH", "sell", "MARKET", wtc_amount)
			  				WtcSetting.last.update(recently_bought: false)

			  				# text to alert that we sold
			  				mailer = Mailer.new
			  				mailer.send_text(text: "Selling WTCETH")
			  			end
			  		else
			  			puts "****Waiting****"
			  		end
			  	else
			  		puts "Couldn't decipher trade symbol"
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
		  # client.kline symbol: 'FUNETH', interval: '5m', methods: methods

		  # As well as partial_book_depth
		  # client.partial_book_depth symbol: 'XRPETH', level: '5', methods: methods

		  # # Create a custom stream
		  # client.single stream: { type: 'aggTrade', symbol: 'XRPETH'}, methods: methods

		  # # Create multiple streams in one call
		  client.multi streams: [{ type: 'kline', symbol: 'FUNETH', interval: '5m'},
		                         { type: 'kline', symbol: 'TRXETH', interval: '5m'},
		                         { type: 'kline', symbol: 'VENETH', interval: '5m'},
		                         { type: 'kline', symbol: 'WTCETH', interval: '5m'}],
		               methods: methods 
		end
	end
end





