Dir["./models/*.rb"].each {|file| require file }
require('./bot')

class RsiMacdAlgorithm

	attr_reader :price_history
	attr_reader :last_rsis

	def initialize(rsiTolerance: 10, price_history: [], buy_zone: 30, sell_zone: 70)
		@rsiTolerance = rsiTolerance
		@price_history = price_history
		@buy_zone = buy_zone
		@sell_zone = sell_zone
		@last_rsis = ""
	end

	def analyze
		# # going to sell 10% of my ven
		# ven_trading_chunks = ven_amount * @percentage_to_sell_with

		# # array of prices up to the index
		# price_history = venEthArray[0, index + 1].map { |eth| eth.closing_price }

		# # optomization, only going to calculate indicators with 500 points of price history
		# if price_history.count > 251
		# 	price_history = price_history[index - 250, index]
		# end

		data = Indicators::Data.new(@price_history)

		# calculate rsi
		rsi = data.calc(:type => :rsi, :params => 14).output

		# calculate MACD
		macdArray = data.calc(:type => :macd, :params => [12, 26, 9]).output

		# reference to rsi so I know whether to buy or sell
		rsiAlert = rsi_recently_crossed_threshold?(rsi)

		# test to see if rsi went to the buy/sell zones and a macd cross
		if macd_recently_crossed?(macdArray) && rsiAlert[:crossed]

			# rsi > 70
			if rsiAlert[:buy]
				# make sure I have enough eth to buy with
				# if eth_amount - eth_trading_chunks > 0

				# 	# "withdraw" the eth that I'm buying with
				# 	eth_amount = eth_amount - eth_trading_chunks

				# 	# amount of ven I'm gaining = amount of eth I'm buying with / price all times 0.0095 which is the amount with the fee taken out
				# 	new_ven = (eth_trading_chunks / ven_eth[:closing_price]) * (1 - @trading_fee)
				# 	ven_amount += new_ven
				# 	recently_bought = true
				# 	recently_bought_price = ven_eth[:closing_price]
				# else
				# 	puts "Ran out of Eth"
				# end
				return "buy"
			# rsi < 30
			elsif rsiAlert[:sell]
				# puts "Selling - RSI: buy: #{rsiAlert[:buy]}, sell: #{rsiAlert[:sell]}"
				# if ven_amount - ven_trading_chunks > 0

				# 	# "withdraw" the ven I'm selling
				# 	ven_amount = ven_amount - ven_trading_chunks

				# 	# price of ven I'm selling in terms of eth
				# 	sell_amount = ven_trading_chunks * ven_eth[:closing_price]

				# 	# take out the fee
				# 	new_eth = sell_amount * (1 - @trading_fee)
				# 	eth_amount += new_eth
				# 	puts "New Eth Amount: #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
				# else
				# 	puts "Ran out of VEN"
				# end
				return "sell"
			end
		else
			return "wait"
		end
	end

	def macd_recently_crossed?(macdArray)

		# formatting the last and 2nd to last histogram height
		firstMacd = format_number_to_be_larger_than_one(macdArray[macdArray.length - 2][0])
		nextMacd = format_number_to_be_larger_than_one(macdArray[macdArray.length - 1][0])

		# divide the 2 to see if there was a switch in sign. 
		# If it went from negative to positive, then the result of the division would negative
		# If it went from positive to negative, then the result of the division would also be negative
		# If it stayed the same sign, then the result of the division would be positive
		if ((firstMacd / nextMacd) < 0)
			true
		else
			false
		end
	end

	# format the number to make sure I dont run into floating point issues
	def format_number_to_be_larger_than_one(number)
		if (number < 1 && number > 0) || (number < 0 && number > -1)
			number = number * 10
		else
			number.to_f
		end
	end

	# just simply calculating whether or not the last 4 rsi numbers crossed into either threshold
	# rsi will always cross before macd which is why I test a few places backwards
	def rsi_recently_crossed_threshold?(rsiArray)
		# set in initializer now
		# @tolerance = 1
		crossed = false
		buy = false
		sell = false
		last_index = rsiArray.count - 1
		buyRsiToInspect = []
		sellRsiToInspect = []
		rsiArray[(last_index - @rsiTolerance)..last_index].each do |rsi|
			if rsi >= @sell_zone
				crossed = true
				sell = true
				sellRsiToInspect.push(rsi)
			elsif rsi <= @buy_zone
				buy = true
				crossed = true
				buyRsiToInspect.push(rsi)
			end
		end
		if buy
			if buyRsiToInspect.count > 1
				if buyRsiToInspect[0] > buyRsiToInspect[(buyRsiToInspect.count - 1)]
					{ crossed: crossed, sell: false, buy: true }
				else
					{ crossed: crossed, sell: false, buy: false }
				end
			else
				{ crossed: crossed, sell: false, buy: false }
			end
		elsif sell
			if sellRsiToInspect.count > 1
				if sellRsiToInspect[0] < sellRsiToInspect[(sellRsiToInspect.count - 1)]
					{ crossed: crossed, sell: true, buy: false }
				else
					{ crossed: crossed, sell: false, buy: false }
				end
			else
				{ crossed: crossed, sell: false, buy: false }
			end
		else
			{ crossed: crossed, sell: false, buy: false }
		end
	end

end