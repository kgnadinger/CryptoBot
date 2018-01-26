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

		# Initialize Indicator Class
		data = Indicators::Data.new(@price_history)

		# calculate rsi
		rsi = data.calc(:type => :rsi, :params => 14).output

		# calculate MACD
		macdArray = data.calc(:type => :macd, :params => [12, 26, 9]).output

		# reference to rsi so I know whether to buy or sell
		rsiAlert = rsi_recently_crossed_threshold?(rsi)

		# test to see if rsi went to the buy/sell zones and a macd cross
		if macd_recently_crossed?(macdArray) && rsiAlert[:crossed]
			if rsiAlert[:buy]
				return "buy"
			elsif rsiAlert[:sell]
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
		crossed = false
		buy = false
		sell = false
		last_index = rsiArray.count - 1
		buyRsiToInspect = []
		sellRsiToInspect = []

		# Inspect the last indexes in rsiArray(up to @tolerance) to see if they crossed the
		# buy and sell zones
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
		# Inspects the 1st and Last Index of the array and sees which way it's trending
		if buy
			if buyRsiToInspect.count > 1
				# is it trending up? Then buy
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
				# is it trending down? Then sell
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