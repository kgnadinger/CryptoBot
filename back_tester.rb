require('./ven_eth')
require('./bot')

class BackTester

	def initialize
		@trading_fee = 0.0005
		@percentage_to_buy_with = 0.10
		@percentage_to_sell_with = 0.10
		@calculating_length = 500
	end

	def go
		# starting ven
		ven_amount = 0

		# starting eth
		eth_amount = 0.01

		# going to buy with 10% of the amount of eth left
		eth_trading_chunks = eth_amount * @percentage_to_buy_with

		# goign to sell 10% of my ven
		ven_trading_chunks = ven_amount * @percentage_to_sell_with

		# Grab all VenEth, ordered from smallest opening_time(integer)
		venEthArray = VenEth.order(:opening_time).select(:id, :closing_price).all

		venEthArray.each_with_index do |ven_eth, index|
			# starting at 34 because that's how much price data I need to use the indicators
			if index > 34
				puts "Index: #{index}"

				# array of prices up to the index
				price_history = venEthArray[0, index + 1].map { |eth| eth.closing_price }

				# optomization, only going to calculate indicators with 500 points of price history
				if price_history.count > 501
					price_history = price_history[index - 500, index]
				end


				data = Indicators::Data.new(price_history)

				# calculate rsi
				rsi = data.calc(:type => :rsi, :params => 14).output

				# calculate MACD
				macdArray = data.calc(:type => :macd, :params => [12, 26, 9]).output

				# reference to rsi so I know whether to buy or sell
				rsiAlert = rsi_recently_crossed_threshold?(rsi, index)

				# test to see if rsi went to the buy/sell zones and a macd cross
				if macd_recently_crossed?(macdArray, index) && rsiAlert[:crossed]

					# rsi > 70
					if rsiAlert[:buy]
						# make sure I have enough eth to buy with
						if eth_amount - eth_trading_chunks > 0

							# "withdraw" the eth that I'm buying with
							eth_amount = eth_amount - eth_trading_chunks

							# amount of ven I'm gaining = amount of eth I'm buying with / price all times 0.0095 which is the amount with the fee taken out
							new_ven = (eth_trading_chunks / ven_eth[:closing_price]) * (1 - @trading_fee)
							ven_amount += new_ven
							puts "New Ven Amount: #{ven_amount}, Price: #{ven_eth[:closing_price] * ven_amount}, Index: #{index}"
						else
							puts "Ran out of Eth"
						end
					# rsi < 30
					elsif rsiAlert[:sell]
						if ven_amount - ven_trading_chunks > 0

							# "withdraw" the ven I'm selling
							ven_amount = ven_amount - ven_trading_chunks

							# price of ven I'm selling in terms of eth
							sell_amount = ven_amount * ven_eth[:closing_price]

							# take out the fee
							new_eth = sell_amount * (1 - @trading_fee)
							eth_amount += new_eth
							puts "New Eth Amount: #{eth_amount}, Price: #{ven_eth[:closing_price]}, Index: #{index}"
						else
							puts "Ran out of VEN"
						end
					end
				end
			end
		end
		puts "Ven Amount = #{ven_amount}, Price in Eth = #{ven_amount * venEthArray.last[:closing_price]}"
		puts "Eth Amount = #{eth_amount}}"
		
	end

	# the macd crosses when the historgram switches sign
	def macd_recently_crossed?(macdArray, index)

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
	def rsi_recently_crossed_threshold?(rsiArray, index)
		tolerance = 4
		crossed = false
		buy = false
		sell = false
		rsiArray[(rsiArray.length - 1 - tolerance)..(rsiArray.length - 1)].each do |rsi|
			if rsi > 70
				crossed = true
				sell = true
			elsif rsi < 30
				buy = true
				crossed = true
			end
		end
		{ crossed: crossed, sell: sell, buy: buy }
	end
end