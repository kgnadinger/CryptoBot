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
		client = Binance::Client::WebSocket.new
		recently_bought_fun_price = 0.0
		recently_bought_trx_price = 0.0
		recently_bought_ven_price = 0.0
		recently_bought_fun = false
		recently_bought_trx = false
		recently_bought_ven = false

		trying_to_enter_market = false
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
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
		  }
		  message = proc { |e| 
		  	hash = eval(e.data)
		  	if trying_to_enter_market
		  		if hash[:s] == "FUNETH"
		  			new_price = hash[:k][:c]
		  			enter_decision = @trade_model.update_price(new_price)
		  			if enter_decision == "buy"
		  				order = create_test_order("FUNETH", "buy", "MARKET", 5)
		  				puts order
		  			elsif enter_decision == "sell"
		  				order = create_test_order("FUNETH", "sell", "MARKET", 10)
		  				puts order
		  			elsif enter_decision == "wait"
		  				puts "Waiting, Price: #{new_price}, limit: #{@trade_model.limit}"
		  			end
		  		end
		  	end
		  	if hash[:k][:x]
		  		puts hash
		  		price_history = []
		  		if hash[:s] == "FUNETH"
		  			puts "FUNETH"
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
		  		end
		  		algorithm = RsiMacdAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 65, sell_zone: 90
		  		puts algorithm.last_rsis
		  		signal = algorithm.analyze
		  		if hash[:s] == "FUNETH"
			  		if signal == "buy"
			  			puts "****Buying****"
			  			if getAmount("ETH").to_f > 0 && !trying_to_enter_market
			  				# create_order("FUNETH", "buy", "MARKET", 5)
			  				@trade_model = FunEthTradeModel.new signal: "buy", closing_price: hash[:k][:c].to_f, eth_amount: getAmount("ETH").to_f
			  				trying_to_enter_market = true
			  				recently_bought_fun = true
			  				recently_bought_fun_price = hash[:k][:c]
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying FUNETH")
			  			else
			  				puts "Out of ETH"
			  			end
			  		elsif recently_bought_fun
			  			if hash[:k][:c].to_f > recently_bought_fun_price * 1.13
				  			puts "***Selling To Keep Profit***"
				  			if getAmount("FUN").to_f > 0
				  				# create_order("FUNETH", "sell", "MARKET", 10)
				  				recently_bought_fun = false
				  				recently_bought_fun_price = 0
				  				mailer.send_text(text: "Selling FUNETH")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling****"
			  			if getAmount("FUN").to_f > 0
			  				# create_order("FUNETH", "sell", "MARKET", 10)
			  				recently_bought_fun = false
				  			recently_bought_fun_price = 0
			  				mailer.send_text(text: "Selling FUNETH")
			  			end
			  		else
			  			puts "****Waiting****"
			  		end
			  	end
		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { puts 'closed' }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }
		  
		  # kline takes an additional named parameter
		  client.kline symbol: 'FUNETH', interval: '5m', methods: methods
		end
	end

	def stream
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
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
			wtc_raw_price_history = price_history("VENETH", '5m', 500)
			wtc_raw_price_history.each do |raw_price|
				wtc_eth = WtcEth.where(opening_time: raw_price[:open_time])
				if wtc_eth && wtc_eth.first
					wtc_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					wtc_eth = VenEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					wtc_eth.save
				end
			end
		  }
		  message = proc { |e| 
		  	hash = eval(e.data)[:data]
		  	if hash[:k][:x]
		  		puts hash
		  		price_history = []
		  		if hash[:s] == "FUNETH"
		  			puts "FUNETH"
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
		  		elsif hash[:s] == "TRXETH"
		  			puts "FUNETH"
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
		  			trx_history = TrxEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = trx_history.map { |f| f.closing_price }
		  		elsif hash[:s] == "VENETH"
		  			puts "VENETH"
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
		  			ven_history = VenEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = ven_history.map { |f| f.closing_price }
		  		elsif hash[:s] == "WTCETH"
		  			puts "WTCETH"
			  		wtc_eth = WtcEth.where(opening_time: hash[:k][:t])
			  		if wtc_eth && wtc_eth.first
			  			wtc_eth.first.update(opening_time: hash[:k][:t], 
											 closing_price: hash[:k][:c], 
											 closing_time: hash[:k][:T],
											 updated_at: DateTime.now)
			  		else
			  			wtc_eth = VenEth.new(opening_time: hash[:k][:t], 
											 closing_price: hash[:k][:c], 
											 closing_time: hash[:k][:T],
											 updated_at: DateTime.now,
											 created_at: DateTime.now)
			  			wtc_eth.save
			  		end
		  			wtc_history = WtcEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = wtc_history.map { |f| f.closing_price }
		  		end
		  		algorithm = RsiMacdAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 35, sell_zone: 68
		  		signal = algorithm.analyze
		  		if hash[:s] == "FUNETH"
			  		if signal == "buy"
			  			puts "****Buying****"
			  			if getAmount("ETH").to_f > 0
			  				create_order("FUNETH", "buy", "MARKET", 5)
			  				f = FunSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f)
			  				f.save
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying FUNETH")
			  			else
			  				puts "Out of ETH"
			  			end
			  		elsif !FunSetting.last.nil? && FunSetting.last.recently_bought?
			  			if hash[:k][:c].to_f > FunSetting.last.recently_bought_price * 1.13
				  			puts "***Selling To Keep Profit***"
				  			if getAmount("FUN").to_f > 0
				  				create_order("FUNETH", "sell", "MARKET", 10)
				  				FunSetting.last.update(recently_bought: false)
				  				mailer.send_text(text: "Selling FUNETH")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling****"
			  			if getAmount("FUN").to_f > 0
			  				create_order("FUNETH", "sell", "MARKET", 10)
			  				FunSetting.last.update(recently_bought: false)
			  				mailer.send_text(text: "Selling FUNETH")
			  			end
			  		else
			  			puts "****Waiting****"
			  		end
			  	elsif hash[:s] == "TRXETH"
			  		if signal == "buy"
			  			puts "****Buying****"
			  			if getAmount("ETH").to_f > 0
			  				create_order("TRXETH", "buy", "MARKET", 5)
			  				f = TrxSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f)
			  				f.save
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying TRXETH")
			  			else
			  				puts "Out of ETH"
			  			end
			  		elsif !TrxSetting.last.nil? && TrxSetting.last.recently_bought?
			  			if hash[:k][:c].to_f > TrxSetting.last.recently_bought_price * 1.19
				  			puts "***Selling TRX To Keep Profit***"
				  			if getAmount("TRX").to_f > 0
				  				create_order("TRXETH", "sell", "MARKET", 10)
				  				TrxSetting.last.update(recently_bought: false)
				  				mailer.send_text(text: "Selling TRXETH")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling****"
			  			if getAmount("TRX").to_f > 0
			  				create_order("TRXETH", "sell", "MARKET", 10)
			  				TrxSetting.last.update(recently_bought: false)
			  				mailer.send_text(text: "Selling TRXETH")
			  			end
			  		else
			  			puts "****Waiting****"
			  		end
			  	elsif hash[:s] == "VENETH"
			  		if signal == "buy"
			  			puts "****Buying VEN****"
			  			if getAmount("ETH").to_f > 0
			  				create_order("VENETH", "buy", "MARKET", 1)
			  				f = VenSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f)
			  				f.save
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying VENETH")
			  			else
			  				puts "Out of ETH"
			  			end
			  		elsif !VenSetting.last.nil? && VenSetting.last.recently_bought?
			  			if hash[:k][:c].to_f > VenSetting.last.recently_bought_price * 1.3
				  			puts "***Selling VEN To Keep Profit***"
				  			if getAmount("VEN").to_f > 0
				  				create_order("VENETH", "sell", "MARKET", 2)
				  				VenSetting.last.update(recently_bought: false)
				  				mailer = Mailer.new
				  				mailer.send_text(text: "Selling VENETH")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling VEN****"
			  			if getAmount("VEN").to_f > 0
			  				create_order("VENETH", "sell", "MARKET", 2)
			  				VenSetting.last.update(recently_bought: false)
			  				mailer.send_text(text: "Selling VENETH")
			  			end
			  		else
			  			puts "****Waiting****"
			  		end
			  	elsif hash[:s] == "WTCETH"
			  		if signal == "buy"
			  			puts "****Buying WTC****"
			  			if getAmount("ETH").to_f > 0
			  				create_order("WTCETH", "buy", "MARKET", 1)
			  				f = WtcSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f)
			  				f.save
			  				mailer = Mailer.new
							mailer.send_text(text: "Buying WTCETH")
			  			else
			  				puts "Out of ETH"
			  			end
			  		elsif !WtcSetting.last.nil? && WtcSetting.last.recently_bought?
			  			if hash[:k][:c].to_f > WtcSetting.last.recently_bought_price * 1.13
				  			puts "***Selling VEN To Keep Profit***"
				  			if getAmount("WTC").to_f > 0
				  				create_order("WTCETH", "sell", "MARKET", 2)
				  				WtcSetting.last.update(recently_bought: false)
				  				mailer = Mailer.new
				  				mailer.send_text(text: "Selling VENETH")
				  			end
				  		end
			  		elsif signal == "sell"
			  			puts "****Selling WTC****"
			  			if getAmount("WTC").to_f > 0
			  				create_order("WTCETH", "sell", "MARKET", 2)
			  				WtcSetting.last.update(recently_bought: false)
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
		                         { type: 'kline', symbol: 'VENETH', interval: '5m'}],
		               methods: methods 
		end
	end
end





