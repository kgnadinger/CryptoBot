require('binance')
require('indicators')
require('./secrets')
require 'eventmachine'
require('./rsi_macd_algorithm')
require('./rsi_algorithm')
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
		@client.account_info(recvWindow: 10000000)
	end

	def exchange_info
		@client.exchange_info()
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

	def get_amount_in_eth(symbol_hash)
		symbol = symbol_hash["asset"]
		coin_amount = symbol_hash["free"].to_f
		case symbol		
		when "WTC"
			last_price = WtcEth.last ? WtcEth.last.closing_price : 0
			coin_amount * last_price
		when "TRX"
			last_price = TrxEth.last ? TrxEth.last.closing_price : 0
			coin_amount * last_price
		when "FUN"
			last_price = FunEth.last ? FunEth.last.closing_price : 0
			coin_amount * last_price
		when "VEN"
			last_price = VenEth.last ? VenEth.last.closing_price : 0
			coin_amount * last_price
		when "XLM"
			last_price = XlmEth.last ? XlmEth.last.closing_price : 0
			coin_amount * last_price
		when "AMB"
			last_price = AmbEth.last ? AmbEth.last.closing_price : 0
			coin_amount * last_price
		else
			full_symbol = symbol + "ETH"
			price_history = price_history(full_symbol, "5m", 1)
			last_price_history = price_history.last
			last_price = last_price_history[:close_price]
			puts "Symbol: #{full_symbol} Price History: #{price_history} Last Price: #{last_price}"
			if last_price
				coin_amount * last_price.to_f
			else
				0
			end
		end
	end

	def save_eth_balance
		eth_total = 0
		account_info["balances"].each do |b|
			amount = b["free"].to_f
			if amount > 0
				symbol = b["asset"]
				if symbol == "ETH"
					eth_total += amount
				else
					eth_total += get_amount_in_eth(b)
				end
			end
		end
		daily_change = 0
		if BotHistory.last
			last_amount = BotHistory.last.close_amount
			daily_change = (eth_total - last_amount) / last_amount
		end
		BotHistory.new(
			close_amount: eth_total,
			daily_change: daily_change,
			created_at: DateTime.now
		).save
		puts "ETH total: #{eth_total}"
	end

	def eng_stream
		trying_to_buy = false
		buy_start_time = DateTime.now.to_time
		buy_ceiling = 0.0
		buy_limit = 0.0

		trying_to_sell = false
		sell_start_time = DateTime.now.to_time
		sell_floor = 0.0
		sell_limit = 0.0

		trade_range = 0.01
		maximum_time_to_trade = 60 * 60
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trade pairs, this occurs at the beginning of the stream
		  	raw_price_history = price_history("ENGETH", '5m', 500)
	  		raw_price_history.each do |raw_price|
				eng_eth = EngEth.where(opening_time: raw_price[:open_time])
				if eng_eth && eng_eth.first
					eng_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					eng_eth = EngEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					eng_eth.save
				end
			end
		  }
		  message = proc { |e| 
		  	# Grab the latest data hash from binance
		  	hash = eval(e.data)[:data]
		  	# if the price is the closing price
		  	if hash[:k][:x]
		  		eng_eth = EngEth.where(opening_time: hash[:k][:t])
		  		if eng_eth && eng_eth.first
		  			eng_eth.first.update(opening_time: hash[:k][:t], 
										 closing_price: hash[:k][:c], 
										 closing_time: hash[:k][:T],
										 updated_at: DateTime.now)
		  		else
		  			eng_eth = EngEth.new(opening_time: hash[:k][:t], 
										 closing_price: hash[:k][:c], 
										 closing_time: hash[:k][:T],
										 updated_at: DateTime.now,
										 created_at: DateTime.now)
		  			eng_eth.save
		  		end
		  		# Grab last 500 EngEth prices
	  			eng_history = EngEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
	  			price_history = eng_history.map { |f| f.closing_price }
		  	end
		  	if trying_to_buy
		  		puts "Trying To Buy **** Current Price: #{hash[:k][:c].to_f.round(10)} Ceiling: #{buy_ceiling.round(10)}, Limit: #{buy_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - buy_start_time > maximum_time_to_trade
		  			trying_to_buy = false
		  		elsif closing_price > buy_ceiling
		  			trying_to_buy = false
		  			# make sure we have enough ETH to buy
		  			eth_amount = getAmount("ETH").to_f * 0.01
		  			if eth_amount > 0
		  				puts "**** Buying ENGETH @ #{closing_price} *****"

		  				eng_amount = (eth_amount / closing_price).ceil
		  				# create a buy order
		  				create_order("ENGETH", "buy", "MARKET", eng_amount)

		  				# log to database that we bought and its price
		  				f = EngSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f, trade_time: DateTime.now)
		  				f.save

		  				# text to alert that we bought
		  				mailer = Mailer.new
						mailer.send_text(text: "Buying ENGETH @ #{closing_price}")
		  			else
		  				puts "Out of ETH"
		  			end
		  		elsif closing_price < buy_limit
		  			buy_ceiling = closing_price * (1 + (trade_range / 2.0))
		  			buy_limit = closing_price * (1 - (trade_range / 2.0))
		  			buy_start_time = DateTime.now.to_time
		  			puts "Adjust Buy Ceiling: #{buy_ceiling.round(10)}, Adjust Limit: #{buy_limit.round(10)}"
		  		end
		  	elsif trying_to_sell
		  		puts "Trying To Sell **** Current Price: #{hash[:k][:c].to_f.round(10)} Floor: #{sell_floor.round(10)}, Limit: #{sell_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - sell_start_time > maximum_time_to_trade
		  			trying_to_sell = false
		  		elsif closing_price < sell_floor
		  			trying_to_sell = false
		  			eng_amount = (getAmount("ENG").to_f * 0.25).ceil
			  		if eng_amount > 0
		  				# sell
		  				create_order("ENGETH", "sell", "MARKET", eng_amount)

		  				puts "**** Selling ENGETH @ #{closing_price} *****"

		  				# text to alert that we sold
		  				mailer = Mailer.new
		  				mailer.send_text(text: "Selling ENGETH @ #{closing_price}")
		  			else
		  				"Out of ENG"
		  			end
		  			# update setting
		  			if !EngSetting.last.nil?
		  				EngSetting.last.update(recently_bought: false, trade_time: DateTime.now)
		  			else
		  				EngSetting.create(recently_bought: false, trade_time: DateTime.now)
		  			end
		  		elsif closing_price > sell_limit
		  			sell_floor = closing_price * (1 - (trade_range / 2.0))
		  			sell_limit = closing_price * (1 + (trade_range / 2.0))
		  			sell_start_time = DateTime.now.to_time
		  			puts "Adjust Sell Ceiling: #{sell_floor.round(10)}, Adjust Limit: #{sell_limit.round(10)}"
		  		end
		  	elsif hash[:k][:x]
		  		# initialize array
		  		price_history = []
		  		if hash[:s] == "ENGETH"
		  			puts "ENGETH"
			  		# Grab last 500 FunEth prices
		  			eng_history = EngEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = eng_history.map { |f| f.closing_price }
		  		end

		  		# Initialize algorithm
		  		algorithm = RsiAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 30, sell_zone: 70
		  		signal = algorithm.analyze # buy, sell or wait
		  		time_between_trades = 60 * 30
		  		if hash[:s] == "ENGETH"
			  		if signal == "buy" && !(!EngSetting.last.nil? && (DateTime.now.to_time - EngSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Buying ENGETH****"
			  			trying_to_buy = true
			  			buy_start_time = DateTime.now.to_time
		  				buy_ceiling = hash[:k][:c].to_f  * (1 + (trade_range / 2.0))
		  				buy_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		# Check if last setting exists and that recently bought is true
			  		elsif !EngSetting.last.nil? && EngSetting.last.recently_bought?
			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > EngSetting.last.recently_bought_price * 1.11
				  			puts "***Selling To Keep Profit***"
				  			trying_to_sell = true
				  			sell_start_time = DateTime.now.to_time
			  				sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  				sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
				  		end
			  		elsif signal == "sell" && !(!EngSetting.last.nil? && (DateTime.now.to_time - EngSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Selling****"
			  			trying_to_sell = true
			  			sell_start_time = DateTime.now.to_time
			  			sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  			sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		else
			  			puts "****Waiting****"
			  		end
			  	
			  	else
			  		puts "Couldn't decipher trade symbol"
			  	end
		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { 
		  	puts 'closed' 
		  	mailer = Mailer.new
		  	mailer.send_text(text: "ENG Closed")
		  	self.eng_stream
		  }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }

		  client.multi streams: [{ type: 'kline', symbol: 'ENGETH', interval: '5m'}],
		               methods: methods 
		end
	end

	def xlm_stream
		trying_to_buy = false
		buy_start_time = DateTime.now.to_time
		buy_ceiling = 0.0
		buy_limit = 0.0

		trying_to_sell = false
		sell_start_time = DateTime.now.to_time
		sell_floor = 0.0
		sell_limit = 0.0

		trade_range = 0.01
		maximum_time_to_trade = 60 * 60
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trade pairs, this occurs at the beginning of the stream
		  	raw_price_history = price_history("XLMETH", '5m', 500)
	  		raw_price_history.each do |raw_price|
				xlm_eth = XlmEth.where(opening_time: raw_price[:open_time])
				if xlm_eth && xlm_eth.first
					xlm_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					xlm_eth = XlmEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					xlm_eth.save
				end
			end
		  }
		  message = proc { |e| 
		  	# Grab the latest data hash from binance
		  	hash = eval(e.data)[:data]
		  	# if the price is the closing price
		  	if hash[:k][:x]
		  		xlm_eth = XlmEth.where(opening_time: hash[:k][:t])
		  		if xlm_eth && xlm_eth.first
		  			xlm_eth.first.update(opening_time: hash[:k][:t], 
										 closing_price: hash[:k][:c], 
										 closing_time: hash[:k][:T],
										 updated_at: DateTime.now)
		  		else
		  			xlm_eth = XlmEth.new(opening_time: hash[:k][:t], 
										 closing_price: hash[:k][:c], 
										 closing_time: hash[:k][:T],
										 updated_at: DateTime.now,
										 created_at: DateTime.now)
		  			xlm_eth.save
		  		end
		  		# Grab last 500 XlmEth prices
	  			xlm_history = XlmEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
	  			price_history = xlm_history.map { |f| f.closing_price }
		  	end
		  	if trying_to_buy
		  		puts "Trying To Buy **** Current Price: #{hash[:k][:c].to_f.round(10)} Ceiling: #{buy_ceiling.round(10)}, Limit: #{buy_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - buy_start_time > maximum_time_to_trade
		  			trying_to_buy = false
		  		elsif closing_price > buy_ceiling
		  			trying_to_buy = false
		  			# make sure we have enough ETH to buy
		  			eth_amount = getAmount("ETH").to_f * 0.01
		  			if eth_amount > 0
		  				puts "**** Buying XLMETH @ #{closing_price} *****"

		  				xlm_amount = (eth_amount / closing_price).ceil
		  				# create a buy order
		  				create_order("XLMETH", "buy", "MARKET", xlm_amount)

		  				# log to database that we bought and its price
		  				f = XlmSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f, trade_time: DateTime.now)
		  				f.save

		  				# text to alert that we bought
		  				mailer = Mailer.new
						mailer.send_text(text: "Buying XLMETH @ #{closing_price}")
		  			else
		  				puts "Out of ETH"
		  			end
		  		elsif closing_price < buy_limit
		  			buy_ceiling = closing_price * (1 + (trade_range / 2.0))
		  			buy_limit = closing_price * (1 - (trade_range / 2.0))
		  			buy_start_time = DateTime.now.to_time
		  			puts "Adjust Buy Ceiling: #{buy_ceiling.round(10)}, Adjust Limit: #{buy_limit.round(10)}"
		  		end
		  	elsif trying_to_sell
		  		puts "Trying To Sell **** Current Price: #{hash[:k][:c].to_f.round(10)} Floor: #{sell_floor.round(10)}, Limit: #{sell_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - sell_start_time > maximum_time_to_trade
		  			trying_to_sell = false
		  		elsif closing_price < sell_floor
		  			trying_to_sell = false
		  			xlm_amount = (getAmount("XLM").to_f * 0.25).ceil
			  		if xlm_amount > 0
		  				# sell
		  				create_order("XLMETH", "sell", "MARKET", xlm_amount)

		  				puts "**** Selling XLMETH @ #{closing_price} *****"

		  				# text to alert that we sold
		  				mailer = Mailer.new
		  				mailer.send_text(text: "Selling XLMETH @ #{closing_price}")
		  			else
		  				"Out of XLM"
		  			end
		  			# update setting
		  			if !XlmSetting.last.nil?
		  				XlmSetting.last.update(recently_bought: false, trade_time: DateTime.now)
		  			else
		  				XlmSetting.create(recently_bought: false, trade_time: DateTime.now)
		  			end
		  		elsif closing_price > sell_limit
		  			sell_floor = closing_price * (1 - (trade_range / 2.0))
		  			sell_limit = closing_price * (1 + (trade_range / 2.0))
		  			sell_start_time = DateTime.now.to_time
		  			puts "Adjust Sell Ceiling: #{sell_floor.round(10)}, Adjust Limit: #{sell_limit.round(10)}"
		  		end
		  	elsif hash[:k][:x]
		  		# initialize array
		  		price_history = []
		  		if hash[:s] == "XLMETH"
		  			puts "XLMETH"
			  		# Grab last 500 FunEth prices
		  			xlm_history = XlmEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = xlm_history.map { |f| f.closing_price }
		  		end

		  		# Initialize algorithm
		  		algorithm = RsiAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 30, sell_zone: 70
		  		signal = algorithm.analyze # buy, sell or wait
		  		time_between_trades = 60 * 30
		  		if hash[:s] == "XLMETH"
			  		if signal == "buy" && !(!XlmSetting.last.nil? && (DateTime.now.to_time - XlmSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Buying XLMETH****"
			  			trying_to_buy = true
			  			buy_start_time = DateTime.now.to_time
		  				buy_ceiling = hash[:k][:c].to_f  * (1 + (trade_range / 2.0))
		  				buy_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		# Check if last setting exists and that recently bought is true
			  		elsif !XlmSetting.last.nil? && XlmSetting.last.recently_bought?
			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > XlmSetting.last.recently_bought_price * 1.11
				  			puts "***Selling To Keep Profit***"
				  			trying_to_sell = true
				  			sell_start_time = DateTime.now.to_time
			  				sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  				sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
				  		end
			  		elsif signal == "sell" && !(!XlmSetting.last.nil? && (DateTime.now.to_time - XlmSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Selling****"
			  			trying_to_sell = true
			  			sell_start_time = DateTime.now.to_time
			  			sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  			sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		else
			  			puts "****Waiting****"
			  		end
			  	
			  	else
			  		puts "Couldn't decipher trade symbol"
			  	end
		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { 
		  	puts 'closed' 
		  	mailer = Mailer.new
		  	mailer.send_text(text: "XLM Closed")
		  	self.xlm_stream
		  }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }

		  client.multi streams: [{ type: 'kline', symbol: 'XLMETH', interval: '5m'}],
		               methods: methods 
		end
	end

	def amb_stream
		trying_to_buy = false
		buy_start_time = DateTime.now.to_time
		buy_ceiling = 0.0
		buy_limit = 0.0

		trying_to_sell = false
		sell_start_time = DateTime.now.to_time
		sell_floor = 0.0
		sell_limit = 0.0

		trade_range = 0.01
		maximum_time_to_trade = 60 * 60
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trade pairs, this occurs at the beginning of the stream
		  	raw_price_history = price_history("AMBETH", '5m', 500)
	  		raw_price_history.each do |raw_price|
				amb_eth = AmbEth.where(opening_time: raw_price[:open_time])
				if amb_eth && amb_eth.first
					amb_eth.first.update(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 updated_at: DateTime.now)
				else 
					amb_eth = AmbEth.new(opening_time: raw_price[:open_time], 
										 closing_price: raw_price[:close_price], 
										 closing_time: raw_price[:close_time],
										 created_at: DateTime.now,
										 updated_at: DateTime.now)
					amb_eth.save
				end
			end
		  }
		  message = proc { |e| 
		  	# Grab the latest data hash from binance
		  	hash = eval(e.data)[:data]
		  	# if the price is the closing price
		  	if hash[:k][:x]
		  		amb_eth = AmbEth.where(opening_time: hash[:k][:t])
		  		if amb_eth && amb_eth.first
		  			amb_eth.first.update(opening_time: hash[:k][:t], 
										 closing_price: hash[:k][:c], 
										 closing_time: hash[:k][:T],
										 updated_at: DateTime.now)
		  		else
		  			amb_eth = AmbEth.new(opening_time: hash[:k][:t], 
										 closing_price: hash[:k][:c], 
										 closing_time: hash[:k][:T],
										 updated_at: DateTime.now,
										 created_at: DateTime.now)
		  			amb_eth.save
		  		end
		  		# Grab last 500 AmbEth prices
	  			amb_history = AmbEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
	  			price_history = amb_history.map { |f| f.closing_price }
		  	end
		  	if trying_to_buy
		  		puts "Trying To Buy **** Current Price: #{hash[:k][:c].to_f.round(10)} Ceiling: #{buy_ceiling.round(10)}, Limit: #{buy_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - buy_start_time > maximum_time_to_trade
		  			trying_to_buy = false
		  		elsif closing_price > buy_ceiling
		  			trying_to_buy = false
		  			# make sure we have enough ETH to buy
		  			eth_amount = getAmount("ETH").to_f * 0.003
		  			if eth_amount > 0
		  				puts "**** Buying AMBETH @ #{closing_price} *****"

		  				amb_amount = (eth_amount / closing_price).ceil
		  				# create a buy order
		  				create_order("AMBETH", "buy", "MARKET", amb_amount)

		  				# log to database that we bought and its price
		  				f = AmbSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f, trade_time: DateTime.now)
		  				f.save

		  				# text to alert that we bought
		  				mailer = Mailer.new
						mailer.send_text(text: "Buying AMBETH")
		  			else
		  				puts "Out of ETH"
		  			end
		  		elsif closing_price < buy_limit
		  			buy_ceiling = closing_price * (1 + (trade_range / 2.0))
		  			buy_limit = closing_price * (1 - (trade_range / 2.0))
		  			buy_start_time = DateTime.now.to_time
		  			puts "Adjust Buy Ceiling: #{buy_ceiling.round(10)}, Adjust Limit: #{buy_limit.round(10)}"
		  		end
		  	elsif trying_to_sell
		  		puts "Trying To Sell **** Current Price: #{hash[:k][:c].to_f.round(10)} Floor: #{sell_floor.round(10)}, Limit: #{sell_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - sell_start_time > maximum_time_to_trade
		  			trying_to_sell = false
		  		elsif closing_price < sell_floor
		  			trying_to_sell = false
		  			amb_amount = (getAmount("AMB").to_f * 0.25).ceil
			  		if amb_amount > 0
		  				# sell
		  				create_order("AMBETH", "sell", "MARKET", amb_amount)

		  				puts "**** Selling AMBETH @ #{closing_price} *****"

		  				# text to alert that we sold
		  				mailer = Mailer.new
		  				mailer.send_text(text: "Selling AMBETH")
		  			else
		  				"Out of AMB"
		  			end
		  			# update setting
		  			if !AmbSetting.last.nil?
		  				AmbSetting.last.update(recently_bought: false, trade_time: DateTime.now)
		  			else
		  				AmbSetting.create(recently_bought: false, trade_time: DateTime.now)
		  			end
		  		elsif closing_price > sell_limit
		  			sell_floor = closing_price * (1 - (trade_range / 2.0))
		  			sell_limit = closing_price * (1 + (trade_range / 2.0))
		  			sell_start_time = DateTime.now.to_time
		  			puts "Adjust Sell Ceiling: #{sell_floor.round(10)}, Adjust Limit: #{sell_limit.round(10)}"
		  		end
		  	elsif hash[:k][:x]
		  		# initialize array
		  		price_history = []
		  		if hash[:s] == "AMBETH"
		  			puts "AMBETH"
			  		# Grab last 500 FunEth prices
		  			amb_history = AmbEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = amb_history.map { |f| f.closing_price }
		  		end

		  		# Initialize algorithm
		  		algorithm = RsiAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 30, sell_zone: 70
		  		signal = algorithm.analyze # buy, sell or wait
		  		time_between_trades = 60 * 30
		  		if hash[:s] == "AMBETH"
			  		if signal == "buy" && !(!AmbSetting.last.nil? && (DateTime.now.to_time - AmbSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Buying AMBETH****"
			  			trying_to_buy = true
			  			buy_start_time = DateTime.now.to_time
		  				buy_ceiling = hash[:k][:c].to_f  * (1 + (trade_range / 2.0))
		  				buy_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		# Check if last setting exists and that recently bought is true
			  		elsif !AmbSetting.last.nil? && AmbSetting.last.recently_bought?
			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > AmbSetting.last.recently_bought_price * 1.11
				  			puts "***Selling To Keep Profit***"
				  			trying_to_sell = true
				  			sell_start_time = DateTime.now.to_time
			  				sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  				sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
				  		end
			  		elsif signal == "sell" && !(!AmbSetting.last.nil? && (DateTime.now.to_time - AmbSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Selling****"
			  			trying_to_sell = true
			  			sell_start_time = DateTime.now.to_time
			  			sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  			sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		else
			  			puts "****Waiting****"
			  		end
			  	
			  	else
			  		puts "Couldn't decipher trade symbol"
			  	end
		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { 
		  	puts 'closed' 
		  	mailer = Mailer.new
		  	mailer.send_text(text: "AMB Closed")
		  	self.amb_stream
		  }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }

		  client.multi streams: [{ type: 'kline', symbol: 'AMBETH', interval: '5m'}],
		               methods: methods 
		end
	end

	def trx_stream
		trying_to_buy = false
		buy_ceiling = 0.0
		buy_limit = 0.0
		buy_start_time = DateTime.now.to_time

		trying_to_sell = false
		sell_floor = 0.0
		sell_limit = 0.0
		sell_start_time = DateTime.now.to_time

		trade_range = 0.01
		maximum_time_to_trade = 60 * 60
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trade pairs, this occurs at the beginning of the stream
		  	raw_price_history = price_history("TRXETH", '5m', 500)
	  		raw_price_history.each do |raw_price|
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
		  }
		  message = proc { |e| 
		  	# Grab the latest data hash from binance
		  	hash = eval(e.data)[:data]
		  	# if the price is the closing price
		  	if hash[:k][:x]
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
		  	end
		  	if trying_to_buy
		  		puts "Trying To Buy **** Current Price: #{hash[:k][:c].to_f.round(10)} Ceiling: #{buy_ceiling.round(10)}, Limit: #{buy_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - buy_start_time > maximum_time_to_trade
		  			trying_to_buy = false
		  		elsif closing_price > buy_ceiling
		  			trying_to_buy = false
		  			# make sure we have enough ETH to buy
		  			eth_amount = getAmount("ETH").to_f * 0.001
		  			if eth_amount > 0
		  				puts "**** Buying TRXETH @ #{closing_price} *****"

		  				trx_amount = (eth_amount / closing_price).ceil
		  				# create a buy order
		  				create_order("TRXETH", "buy", "MARKET", trx_amount)

		  				# log to database that we bought and its price
		  				f = TrxSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f, trade_time: DateTime.now)
		  				f.save

		  				# text to alert that we bought
		  				mailer = Mailer.new
						mailer.send_text(text: "Buying TRXETH")
		  			else
		  				puts "Out of ETH"
		  			end
		  		elsif closing_price < buy_limit
		  			buy_ceiling = closing_price * (1 + (trade_range / 2.0))
		  			buy_limit = closing_price * (1 - (trade_range / 2.0))
		  			buy_start_time = DateTime.now.to_time
		  			puts "Adjust Buy Ceiling: #{buy_ceiling.round(10)}, Adjust Limit: #{buy_limit.round(10)}"
		  		end
		  	elsif trying_to_sell
		  		puts "Trying To Sell **** Current Price: #{hash[:k][:c].to_f.round(10)} Floor: #{sell_floor.round(10)}, Limit: #{sell_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - sell_start_time > maximum_time_to_trade
		  			trying_to_sell = false
		  		elsif closing_price < sell_floor
		  			trying_to_sell = false
		  			trx_amount = (getAmount("TRX").to_f * 0.5).ceil
			  		if trx_amount > 0
		  				# sell
		  				create_order("TRXETH", "sell", "MARKET", trx_amount)

		  				puts "**** Selling TRXETH @ #{closing_price} *****"

		  				# text to alert that we sold
		  				mailer = Mailer.new
		  				mailer.send_text(text: "Selling TRXETH")
		  			else
		  				"Out of TRX"
		  			end
		  			# update setting
		  			if !TrxSetting.last.nil?
		  				TrxSetting.last.update(recently_bought: false, trade_time: DateTime.now)
		  			else
		  				TrxSetting.create(recently_bought: false, trade_time: DateTime.now)
		  			end
		  		elsif closing_price > sell_limit
		  			sell_floor = closing_price * (1 - (trade_range / 2.0))
		  			sell_limit = closing_price * (1 + (trade_range / 2.0))
		  			sell_start_time = DateTime.now.to_time
		  			puts "Adjust Sell Ceiling: #{sell_floor.round(10)}, Adjust Limit: #{sell_limit.round(10)}"
		  		end
		  	elsif hash[:k][:x]
		  		# initialize array
		  		price_history = []
		  		if hash[:s] == "TRXETH"
		  			puts "TRXETH"
			  		# Grab last 500 FunEth prices
		  			trx_history = TrxEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = trx_history.map { |f| f.closing_price }
		  		end

		  		# Initialize algorithm
		  		algorithm = RsiAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 30, sell_zone: 70
		  		signal = algorithm.analyze # buy, sell or wait
		  		time_between_trades = 60 * 30
		  		if hash[:s] == "TRXETH"
			  		if signal == "buy" && !(!TrxSetting.last.nil? && (DateTime.now.to_time - TrxSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Buying TRXETH****"
			  			trying_to_buy = true
			  			buy_start_time = DateTime.now.to_time
		  				buy_ceiling = hash[:k][:c].to_f  * (1 + (trade_range / 2.0))
		  				buy_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		# Check if last setting exists and that recently bought is true
			  		elsif !TrxSetting.last.nil? && TrxSetting.last.recently_bought?
			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > TrxSetting.last.recently_bought_price * 1.11
				  			puts "***Selling To Keep Profit***"
				  			trying_to_sell = true
				  			sell_start_time = DateTime.now.to_time
			  				sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  				sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
				  		end
			  		elsif signal == "sell" && !(!TrxSetting.last.nil? && (DateTime.now.to_time - TrxSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Selling****"
			  			trying_to_sell = true
			  			sell_start_time = DateTime.now.to_time
			  			sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  			sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		else
			  			puts "****Waiting****"
			  		end
			  	
			  	else
			  		puts "Couldn't decipher trade symbol"
			  	end
		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { 
		  	puts 'closed' 
		  	mailer = Mailer.new
		  	mailer.send_text(text: "TRX Closed")
		  	self.trx_stream
		  }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }

		  client.multi streams: [{ type: 'kline', symbol: 'TRXETH', interval: '5m'}],
		               methods: methods 
		end
	end

	def ven_stream
		trying_to_buy = false
		buy_ceiling = 0.0
		buy_limit = 0.0
		buy_start_time = DateTime.now.to_time

		trying_to_sell = false
		sell_floor = 0.0
		sell_limit = 0.0
		sell_start_time = DateTime.now.to_time

		trade_range = 0.03
		maximum_time_to_trade = 60 * 60
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trade pairs, this occurs at the beginning of the stream
		  	raw_price_history = price_history("VENETH", '5m', 500)
	  		raw_price_history.each do |raw_price|
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
		  }
		  message = proc { |e| 
		  	# Grab the latest data hash from binance
		  	hash = eval(e.data)[:data]
		  	# if the price is the closing price
		  	if hash[:k][:x]
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
	  			fun_history = VenEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
	  			price_history = fun_history.map { |f| f.closing_price }
		  	end
		  	if trying_to_buy
		  		puts "Trying To Buy **** Current Price: #{hash[:k][:c].to_f.round(10)} Ceiling: #{buy_ceiling.round(10)}, Limit: #{buy_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - buy_start_time > maximum_time_to_trade
		  			trying_to_buy = false
		  		elsif closing_price > buy_ceiling
		  			trying_to_buy = false
		  			# make sure we have enough ETH to buy
		  			eth_amount = getAmount("ETH").to_f * 0.05
		  			if eth_amount > 0
		  				puts "**** Buying VENETH @ #{closing_price} *****"

		  				ven_amount = (eth_amount / closing_price).ceil
		  				# create a buy order
		  				create_order("VENETH", "buy", "MARKET", ven_amount)

		  				# log to database that we bought and its price
		  				f = VenSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f, trade_time: DateTime.now)
		  				f.save

		  				# text to alert that we bought
		  				mailer = Mailer.new
						mailer.send_text(text: "Buying VENETH")
		  			else
		  				puts "Out of ETH"
		  			end
		  		elsif closing_price < buy_limit
		  			buy_ceiling = closing_price * (1 + (trade_range / 2.0))
		  			buy_limit = closing_price * (1 - (trade_range / 2.0))
		  			buy_start_time = DateTime.now.to_time
		  			puts "Adjust Buy Ceiling: #{buy_ceiling.round(10)}, Adjust Limit: #{buy_limit.round(10)}"
		  		end
		  	elsif trying_to_sell
		  		puts "Trying To Sell **** Current Price: #{hash[:k][:c].to_f.round(10)} Floor: #{sell_floor.round(10)}, Limit: #{sell_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - sell_start_time > maximum_time_to_trade
		  			trying_to_sell = false
		  		elsif closing_price < sell_floor
		  			trying_to_sell = false
		  			ven_amount = (getAmount("VEN").to_f * 0.25).ceil
			  		if ven_amount > 0
		  				# sell
		  				create_order("VENETH", "sell", "MARKET", ven_amount)

		  				puts "**** Selling VENETH @ #{closing_price} *****"

		  				# text to alert that we sold
		  				mailer = Mailer.new
		  				mailer.send_text(text: "Selling VENETH")
		  			else
		  				"Out of VEN"
		  			end
		  			# update setting
		  			if !VenSetting.last.nil?
		  				VenSetting.last.update(recently_bought: false, trade_time: DateTime.now)
		  			else
		  				VenSetting.create(recently_bought: false, trade_time: DateTime.now)
		  			end
		  		elsif closing_price > sell_limit
		  			sell_floor = closing_price * (1 - (trade_range / 2.0))
		  			sell_limit = closing_price * (1 + (trade_range / 2.0))
		  			sell_start_time = DateTime.now.to_time
		  			puts "Adjust Sell Ceiling: #{sell_floor.round(10)}, Adjust Limit: #{sell_limit.round(10)}"
		  		end
		  	elsif hash[:k][:x]
		  		# initialize array
		  		price_history = []
		  		if hash[:s] == "VENETH"
		  			puts "VENETH"
			  		# Grab last 500 VenEth prices
		  			ven_history = VenEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = ven_history.map { |f| f.closing_price }
		  		end

		  		# Initialize algorithm
		  		algorithm = RsiAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 30, sell_zone: 70
		  		signal = algorithm.analyze # buy, sell or wait
		  		time_between_trades = 60 * 30
		  		if hash[:s] == "VENETH"
			  		if signal == "buy" && !(!VenSetting.last.nil? && (DateTime.now.to_time - VenSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Buying VENETH****"
			  			trying_to_buy = true
			  			buy_start_time = DateTime.now.to_time
		  				buy_ceiling = hash[:k][:c].to_f  * (1 + (trade_range / 2.0))
		  				buy_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		# Check if last setting exists and that recently bought is true
			  		elsif !VenSetting.last.nil? && VenSetting.last.recently_bought?
			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > VenSetting.last.recently_bought_price * 1.08
				  			puts "***Selling To Keep Profit***"
				  			trying_to_sell = true
				  			sell_start_time = DateTime.now.to_time
			  				sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  				sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
				  		end
			  		elsif signal == "sell" && !(!VenSetting.last.nil? && (DateTime.now.to_time - VenSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Selling****"
			  			trying_to_sell = true
			  			sell_start_time = DateTime.now.to_time
			  			sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  			sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		else
			  			puts "****Waiting****"
			  		end
			  	
			  	else
			  		puts "Couldn't decipher trade symbol"
			  	end
		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { 
		  	puts 'closed' 
		  	mailer = Mailer.new
		  	mailer.send_text(text: "VEN Closed")
		  	self.ven_stream
		  }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }

		  client.multi streams: [{ type: 'kline', symbol: 'VENETH', interval: '5m'}],
		               methods: methods 
		end
	end



	def wtc_stream
		trying_to_buy = false
		buy_ceiling = 0.0
		buy_limit = 0.0
		buy_start_time = DateTime.now.to_time

		trying_to_sell = false
		sell_floor = 0.0
		sell_limit = 0.0
		sell_start_time = DateTime.now.to_time

		trade_range = 0.03
		maximum_time_to_trade = 60 * 60
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trading pairs, this occurs at the beginning of the stream
		  	raw_price_history = price_history("WTCETH", '5m', 500)
	  		raw_price_history.each do |raw_price|
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
	  			fun_history = WtcEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
	  			price_history = fun_history.map { |f| f.closing_price }
		  	end
		  	if trying_to_buy
		  		puts "Trying To Buy **** Current Price: #{hash[:k][:c].to_f.round(10)} Ceiling: #{buy_ceiling.round(10)}, Limit: #{buy_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - buy_start_time > maximum_time_to_trade
		  			trying_to_buy = false
		  		elsif closing_price > buy_ceiling
		  			trying_to_buy = false
		  			# make sure we have enough ETH to buy
		  			eth_amount = getAmount("ETH").to_f * 0.05
		  			if eth_amount > 0
		  				puts "**** Buying WTCETH @ #{closing_price} *****"
		  				wtc_amount = (eth_amount / closing_price).round(2)
		  				# create a buy order
		  				create_order("WTCETH", "buy", "MARKET", wtc_amount)

		  				# log to database that we bought and its price
		  				f = WtcSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f, trade_time: DateTime.now)
		  				f.save

		  				# text to alert that we bought
		  				mailer = Mailer.new
						mailer.send_text(text: "Buying WTCETH")
		  			else
		  				puts "Out of ETH"
		  			end
		  		elsif closing_price < buy_limit
		  			buy_ceiling = closing_price * (1 + (trade_range / 2.0))
		  			buy_limit = closing_price * (1 - (trade_range / 2.0))
		  			buy_start_time = DateTime.now.to_time
		  			puts "Adjust Buy Ceiling: #{buy_ceiling.round(10)}, Adjust Limit: #{buy_limit.round(10)}"
		  		end
		  	elsif trying_to_sell
		  		puts "Trying To Sell **** Current Price: #{hash[:k][:c].to_f.round(10)} Floor: #{sell_floor.round(10)}, Limit: #{sell_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - sell_start_time > maximum_time_to_trade
		  			trying_to_sell = false
		  		elsif closing_price < sell_floor
		  			trying_to_sell = false
		  			wtc_amount = (getAmount("WTC").to_f * 0.25).round(2)
			  		if wtc_amount > 0
		  				# sell
		  				create_order("WTCETH", "sell", "MARKET", wtc_amount)

		  				puts "**** Selling WTCETH @ #{closing_price} *****"

		  				# text to alert that we sold
		  				mailer = Mailer.new
		  				mailer.send_text(text: "Selling WTCETH")
		  			else
		  				"Out of WTC"
		  			end
		  			# update setting
		  			if !WtcSetting.last.nil?
		  				WtcSetting.last.update(recently_bought: false, trade_time: DateTime.now)
		  			else
		  				WtcSetting.create(recently_bought: false, trade_time: DateTime.now)
		  			end
		  		elsif closing_price > sell_limit
		  			sell_floor = closing_price * (1 - (trade_range / 2.0))
		  			sell_limit = closing_price * (1 + (trade_range / 2.0))
		  			sell_start_time = DateTime.now.to_time
		  			puts "Adjust Sell Ceiling: #{sell_floor.round(10)}, Adjust Limit: #{sell_limit.round(10)}"
		  		end
		  	elsif hash[:k][:x]
		  		# initialize array
		  		price_history = []
		  		if hash[:s] == "WTCETH"
		  			puts "WTCETH"
			  		# Grab last 500 WtcEth prices
		  			wtc_history = WtcEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = wtc_history.map { |f| f.closing_price }
		  		end

		  		# Initialize algorithm
		  		algorithm = RsiAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 30, sell_zone: 70
		  		signal = algorithm.analyze # buy, sell or wait
		  		time_between_trades = 60 * 60
		  		if hash[:s] == "WTCETH"
			  		if signal == "buy" && !(!WtcSetting.last.nil? && (DateTime.now.to_time - WtcSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Buying WTCETH****"
			  			trying_to_buy = true
			  			buy_start_time = DateTime.now.to_time
		  				buy_ceiling = hash[:k][:c].to_f  * (1 + (trade_range / 2.0))
		  				buy_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		# Check if last setting exists and that recently bought is true
			  		elsif !WtcSetting.last.nil? && WtcSetting.last.recently_bought?
			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > WtcSetting.last.recently_bought_price * 1.08
				  			puts "***Selling To Keep Profit***"
				  			trying_to_sell = true
				  			sell_start_time = DateTime.now.to_time
			  				sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  				sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
				  		end
			  		elsif signal == "sell" && !(!WtcSetting.last.nil? && (DateTime.now.to_time - WtcSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Selling****"
			  			trying_to_sell = true
			  			sell_start_time = DateTime.now.to_time
			  			sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  			sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		else
			  			puts "****Waiting****"
			  		end
			  	
			  	else
			  		puts "Couldn't decipher trade symbol"
			  	end
		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { 
		  	puts 'closed' 
		  	mailer = Mailer.new
		  	mailer.send_text(text: "WTC Closed")
		  	self.wtc_stream
		  }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }

		  client.multi streams: [{ type: 'kline', symbol: 'WTCETH', interval: '5m'}],
		               methods: methods 
		end
	end

	def fun_stream
		trying_to_buy = false
		buy_ceiling = 0.0
		buy_limit = 0.0
		buy_start_time = DateTime.now.to_time

		trying_to_sell = false
		sell_floor = 0.0
		sell_limit = 0.0
		sell_start_time = DateTime.now.to_time

		trade_range = 0.01
		maximum_time_to_trade = 60 * 60
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trade pairs, this occurs at the beginning of the stream
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
		  	# Grab the latest data hash from binance
		  	hash = eval(e.data)[:data]
		  	# if the price is the closing price
		  	if hash[:k][:x]
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
		  	end
		  	if trying_to_buy
		  		puts "Trying To Buy **** Current Price: #{hash[:k][:c].to_f.round(10)} Ceiling: #{buy_ceiling.round(10)}, Limit: #{buy_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - buy_start_time > maximum_time_to_trade
		  			trying_to_buy = false
		  		elsif closing_price > buy_ceiling
		  			trying_to_buy = false
		  			# make sure we have enough ETH to buy
		  			eth_amount = getAmount("ETH").to_f * 0.003
		  			if eth_amount > 0
		  				puts "**** Buying FUNETH @ #{closing_price} *****"

		  				fun_amount = (eth_amount / closing_price).ceil
		  				# create a buy order
		  				create_order("FUNETH", "buy", "MARKET", fun_amount)

		  				# log to database that we bought and its price
		  				f = FunSetting.new(recently_bought: true, recently_bought_price: hash[:k][:c].to_f, trade_time: DateTime.now)
		  				f.save

		  				# text to alert that we bought
		  				mailer = Mailer.new
						mailer.send_text(text: "Buying FUNETH")
		  			else
		  				puts "Out of ETH"
		  			end
		  		elsif closing_price < buy_limit
		  			buy_ceiling = closing_price * (1 + (trade_range / 2.0))
		  			buy_limit = closing_price * (1 - (trade_range / 2.0))
		  			buy_start_time = DateTime.now.to_time
		  			puts "Adjust Buy Ceiling: #{buy_ceiling.round(10)}, Adjust Limit: #{buy_limit.round(10)}"
		  		end
		  	elsif trying_to_sell
		  		puts "Trying To Sell **** Current Price: #{hash[:k][:c].to_f.round(10)} Floor: #{sell_floor.round(10)}, Limit: #{sell_limit.round(10)}"
		  		closing_price = hash[:k][:c].to_f
		  		if DateTime.now.to_time - sell_start_time > maximum_time_to_trade
		  			trying_to_sell = false
		  		elsif closing_price < sell_floor
		  			trying_to_sell = false
		  			fun_amount = (getAmount("FUN").to_f * 0.75).ceil
			  		if fun_amount > 0
		  				# sell
		  				create_order("FUNETH", "sell", "MARKET", fun_amount)

		  				puts "**** Selling FUNETH @ #{closing_price} *****"

		  				# text to alert that we sold
		  				mailer = Mailer.new
		  				mailer.send_text(text: "Selling FUNETH @ #{closing_price}")
		  			else
		  				"Out of FUN"
		  			end
		  			# update setting
		  			if !FunSetting.last.nil?
		  				FunSetting.last.update(recently_bought: false, trade_time: DateTime.now)
		  			else
		  				FunSetting.create(recently_bought: false, trade_time: DateTime.now)
		  			end
		  		elsif closing_price > sell_limit
		  			sell_floor = closing_price * (1 - (trade_range / 2.0))
		  			sell_limit = closing_price * (1 + (trade_range / 2.0))
		  			sell_start_time = DateTime.now.to_time
		  			puts "Adjust Sell Ceiling: #{sell_floor.round(10)}, Adjust Limit: #{sell_limit.round(10)}"
		  		end
		  	elsif hash[:k][:x]
		  		# initialize array
		  		price_history = []
		  		if hash[:s] == "FUNETH"
		  			puts "FUNETH"
			  		# Grab last 500 FunEth prices
		  			fun_history = FunEth.reverse_order(:opening_time).select(:id, :closing_price, :opening_time).limit(500).all.sort { |d,e| d.opening_time <=> e.opening_time }
		  			price_history = fun_history.map { |f| f.closing_price }
		  		end

		  		# Initialize algorithm
		  		algorithm = RsiAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 30, sell_zone: 70
		  		signal = algorithm.analyze # buy, sell or wait
		  		time_between_trades = 60 * 60
		  		if hash[:s] == "FUNETH"
			  		if signal == "buy" && !(!FunSetting.last.nil? && (DateTime.now.to_time - FunSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Buying FUNETH****"
			  			trying_to_buy = true
			  			buy_start_time = DateTime.now.to_time
		  				buy_ceiling = hash[:k][:c].to_f  * (1 + (trade_range / 2.0))
		  				buy_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		# Check if last setting exists and that recently bought is true
			  		elsif !FunSetting.last.nil? && FunSetting.last.recently_bought?
			  			# is the new price larger than the last bought price * multiplier?
			  			if hash[:k][:c].to_f > FunSetting.last.recently_bought_price * 1.11
				  			puts "***Selling To Keep Profit***"
				  			trying_to_sell = true
				  			sell_start_time = DateTime.now.to_time
			  				sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  				sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
				  		end
			  		elsif signal == "sell" && !(!FunSetting.last.nil? && (DateTime.now.to_time - FunSetting.last.trade_time.to_time < time_between_trades))
			  			puts "****Selling****"
			  			trying_to_sell = true
			  			sell_start_time = DateTime.now.to_time
			  			sell_floor = hash[:k][:c].to_f  * (1 - (trade_range / 2.0))
			  			sell_limit = hash[:k][:c].to_f * (1 - (trade_range / 2.0))
			  		else
			  			puts "****Waiting****"
			  		end
			  	
			  	else
			  		puts "Couldn't decipher trade symbol"
			  	end
		  	end
		  	
		  }
		  error   = proc { |e| puts e }
		  close   = proc { 
		  	puts 'closed' 
		  	mailer = Mailer.new
		  	mailer.send_text(text: "FUN Closed")
		  	self.fun_stream
		  }

		  # Bundle our event handlers into Hash
		  methods = { open: open, message: message, error: error, close: close }

		  client.multi streams: [{ type: 'kline', symbol: 'FUNETH', interval: '5m'}],
		               methods: methods 
		end
	end

	# main bot method for live trade
	def stream
		client = Binance::Client::WebSocket.new
		EM.run do
		  # Create event handlers
		  open    = proc { 
		  	puts 'connected' 
		  	# Download recent prices for trade pairs, this occurs at the beginning of the stream
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
		  		algorithm = RsiMacdAlgorithm.new rsiTolerance: 10, price_history: price_history, buy_zone: 30, sell_zone: 70
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
				  			if fun_amount > 0

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
				  		if fun_amount > 0

			  				# sell
			  				create_order("FUNETH", "sell", "MARKET", fun_amount)

			  				# update setting
			  				if !FunSetting.last.nil?
			  					FunSetting.last.update(recently_bought: false)
			  				end

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
			  				if !TrxSetting.last.nil?
			  					TrxSetting.last.update(recently_bought: false)
			  				end

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
			  				if !VenSetting.last.nil?
			  					VenSetting.last.update(recently_bought: false)
			  				end

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
			  				puts "WTF Amount: #{wtc_amount}"
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
				  				if !WtcSetting.last.nil?
				  					WtcSetting.last.update(recently_bought: false)
				  				end

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





