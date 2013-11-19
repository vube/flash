/*****************************************************
*  
*  Copyright 2009 Akamai Technologies, Inc.  All Rights Reserved.
*  
*****************************************************
*  The contents of this file are subject to the Mozilla Public License
*  Version 1.1 (the "License"); you may not use this file except in
*  compliance with the License. You may obtain a copy of the License at
*  http://www.mozilla.org/MPL/
*   
*  Software distributed under the License is distributed on an "AS IS"
*  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
*  License for the specific language governing rights and limitations
*  under the License.
*   
*  
*  The Initial Developer of the Original Code is Adobe Systems Incorporated.
*  Portions created by Adobe Systems Incorporated are Copyright (C) 2009 Adobe Systems 
*  Incorporated. All Rights Reserved.
* 
*****************************************************/
package org.osmf.net.httpstreaming
{
	import org.osmf.net.SwitchingRuleBase;
	import org.osmf.logging.Logger;
	import org.osmf.logging.Log;

	[ExcludeClass]
	
	/**
	 * @private
	 * 
	 * Switching rule that makes decisions based on the download ratio.
	 **/
	public class DownloadRatioRule extends SwitchingRuleBase
	{
		/**
		 * Constructor
		 * 
		 *  @langversion 3.0
		 *  @playerversion Flash 10
		 *  @playerversion AIR 1.5
		 *  @productversion OSMF 1.0
		 */		
		public function DownloadRatioRule
			( metrics:HTTPNetStreamMetrics
			, aggressiveUpswitch:Boolean=true
			, minFragmentsBetweenSwitch:int=2
			, downshiftSafetyFactor:Number=0.9
			, upshiftSafetyFactor:Number=2.0
			, cacheThreshold:Number=75.0
			, hardSwitchThreshold:Number=1.5
			, hardSwitchMaximum:int=1
			)
		{
			super(metrics);
			
			this.aggressiveUpswitch = aggressiveUpswitch;
			this.minFragmentsBetweenSwitch = minFragmentsBetweenSwitch;
			this.downshiftSafetyFactor = downshiftSafetyFactor;
			this.upshiftSafetyFactor = upshiftSafetyFactor;
			this.cacheThreshold = cacheThreshold;
			this.hardSwitchThreshold = hardSwitchThreshold;
			this.hardSwitchMaximum = hardSwitchMaximum;
		}
		
		/**
		 * The new bitrate index to which this rule recommends switching. If the rule has no change request it will
		 * return a value of -1. 
		 *  
		 *  @langversion 3.0
		 *  @playerversion Flash 10
		 *  @playerversion AIR 1.5
		 *  @productversion OSMF 1.0
		 */
		override public function getNewIndex():int
		{
			// XXX IMPORTANT NOTE: WE AREN'T YET SETTING BUFFER TIME UPWARDS IN
			// NON-SEEK SITUATIONS. NEED TO DO THIS SO RUNNING DRY IS LESS PAINFUL.
				
			// We work in ratios so that we can cancel kbps out of all the equations.
			//
			// The downloadRatio is
			//	      "playback time of last segment downloaded" /
			//        "amount of time it took to download that whole segment, from
			//             request to finished"
			// The switchRatio[proposed] is 
			//        "claimed rate of proposed quality" /
			//        "claimed rate of current quality"
			//
			// There are exactly four cases we need to deal with:
			// 1. The downloadRatio is < 1 and < switchRatio[current-1]:
			//        Bandwidth is way down, switch to lowest rate immediately
			//        (even if there's an intermediate that might work).
			// 2. The downloadRatio is < 1 but >= switchRatio[current-1]:
			//        We should be able to keep going if we go down one level.
			// 3. The lastDownloadRatio is >= 1 but < switchRatio[current+1]
			//    OR no available rate is higher than current:
			//        Steady state where we like to be. Don't touch any knobs.
			// 4. The lastDownloadRatio is >= 1 and > switchRatio[current+1]:
			//        We can go up to rate N where N is the highest N for which
			//        downloadRatio is still > switchRatio[N] (but see caution
			//        about high downloadRatio caused by cached response).
			//
			// XXX Note: We don't currently do this, but we can hold off loading
			// for a bit if and only if we are in state 3 AND the downloadRatio
			// is significantly >= 1 (in addition to holding off loading if
			// bufferLength is growing too far).
			//
			// Note: There is a danger that downloadRatio is absurdly high
			// because it is reflecting cached data. If that is detected, then
			// in case 4 the switch up should only be a single quality level
			// upwards rather than switching to the top rate instantly, just in
			// case even one level up is actually too high a rate in reality.
			//
			
			var proposedIndex:int = -1;
			var switchRatio:Number;
			var moreDetail:String;
			var aBitMore:String = "";

			if (lastSwitchCounter + minFragmentsBetweenSwitch > httpMetrics.fragmentCounter)
			{
				return proposedIndex;
			}

			if (httpMetrics.downloadRatio < 1.0)
			{
				// Cases #1 and #2

				// First check to see if we are even able to switch down.
				if (httpMetrics.currentIndex > 0
					&& !(hardSwitchCount >= hardSwitchMaximum && isHardSwitch(httpMetrics.currentIndex - 1)))
				{
					proposedIndex = httpMetrics.currentIndex - 1

					// Find the most appropriate stream to downswitch to.
					while (--proposedIndex >= 0)
					{
						// Do not allow a hard transition if we've already performed one
						if (hardSwitchCount >= hardSwitchMaximum && isHardSwitch(proposedIndex))
						{
							++proposedIndex;
							aBitMore = " and > a hard switch";
							break;
						}

						switchRatio = getSwitchRatio(proposedIndex, true)

						if (httpMetrics.downloadRatio > switchRatio)
						{
							// Found one that's too high.
							++proposedIndex;
							aBitMore = " and > " + switchRatio;
							break;
						}
					}

					if (proposedIndex < 0)
					{
						proposedIndex = 0;
					}

					moreDetail = "downloadRatio was " + httpMetrics.downloadRatio + " <= " + getSwitchRatio(proposedIndex, true) + aBitMore;
				}
			}
			else if (httpMetrics.downloadRatio > cacheThreshold)
			{
				// Cache, don't touch anything
			}
			else
			{
				// Cases #3 and #4
				
				// First check to see if we are able to switch up.
				if (httpMetrics.currentIndex < httpMetrics.maxAllowedIndex
					&& !(hardSwitchCount >= hardSwitchMaximum && isHardSwitch(httpMetrics.currentIndex + 1))) 
				{
					switchRatio = getSwitchRatio(httpMetrics.currentIndex + 1, false);
					if (httpMetrics.downloadRatio < switchRatio)
					{
						// Case #3, don't touch anything, we're where we want to be.
					}
					else
					{
						// Is the last download ratio suspiciously high (cached data),
						// or has aggressive upswitch been turned off?
						// XXX 100.0 s/b constant value
						if (httpMetrics.downloadRatio > cacheThreshold || !aggressiveUpswitch)
						{
							// Switch up one.
							proposedIndex = httpMetrics.currentIndex + 1
							moreDetail = "downloadRatio was " + httpMetrics.downloadRatio + " >= " + switchRatio;
						}
						else
						{
							// Find the most appropriate stream to upswitch to.
							while (++proposedIndex < httpMetrics.maxAllowedIndex + 1)
							{
								// Do not allow a hard transition if we've already performed one
								if (hardSwitchCount >= hardSwitchMaximum && isHardSwitch(proposedIndex))
								{
									aBitMore = " and < a hard switch";
									break;
								}
								switchRatio = getSwitchRatio(proposedIndex, false)
								if (httpMetrics.downloadRatio < switchRatio)
								{
									// Found one that's too high.
									aBitMore = " and < " + switchRatio;
									break;
								}
							}
							--proposedIndex;
							moreDetail = "downloadRatio was " + httpMetrics.downloadRatio + " >= " + getSwitchRatio(proposedIndex, false) + aBitMore;
						}
					}
				}
			}

			CONFIG::LOGGING
			{
        		if (proposedIndex != -1 && proposedIndex != metrics.currentIndex)
        		{
        			if (isHardSwitch(proposedIndex))
        			{
        				// Only allow a hard transition if we've had two fragments in a row demand it
        				if (hardSwitchLimiter == httpMetrics.fragmentCounter - 1)
        				{
	        				++hardSwitchCount;
	        				hardSwitchLimiter = 0;
        				}
        				else
        				{
        					proposedIndex = -1;
	        				hardSwitchLimiter = httpMetrics.fragmentCounter;
        				}
        			}

        			if (proposedIndex != -1)
        			{
						lastSwitchCounter = httpMetrics.fragmentCounter;
        				debug("getNewIndex() - about to return: " + proposedIndex + " from " + metrics.currentIndex
        					+ ", hard=" + isHardSwitch(proposedIndex)
        					+ ", bitrate=" + httpMetrics.getBitrateForIndex(proposedIndex)
        					+ ", detail=" + moreDetail);
        			}
    			} 
        	}
			
			return proposedIndex;
		}
		
		private function isHardSwitch(index:int):Boolean
		{
			if((Number(index) > hardSwitchThreshold && metrics.currentIndex < hardSwitchThreshold) ||
				(Number(index) < hardSwitchThreshold && metrics.currentIndex > hardSwitchThreshold))
			{
				return true
			}

			return false
		}

		private function getSwitchRatio(index:int, down:Boolean):Number
		{
			var factor:Number = down ? downshiftSafetyFactor : upshiftSafetyFactor;
			// Double up on the safety factor if the transition is hard
			if (isHardSwitch(index))
			{
				factor *= factor / 1
			}

			return httpMetrics.getBitrateForIndex(index) / httpMetrics.getBitrateForIndex(metrics.currentIndex) * factor;
		}
		
		private function get httpMetrics():HTTPNetStreamMetrics
		{
			return metrics as HTTPNetStreamMetrics;
		}
		
		CONFIG::LOGGING
		{
		private function debug(s:String):void
		{
			logger.debug(s);
		}
		}

		private var aggressiveUpswitch:Boolean = false;
		private var minFragmentsBetweenSwitch:int = 2;
		private var downshiftSafetyFactor:Number = 0.9;
		private var upshiftSafetyFactor:Number = 2.0;
		private var cacheThreshold:Number = 75.0;
		private var hardSwitchThreshold:Number = 1.5;
		private var hardSwitchMaximum:int = 1;

		private var lastSwitchCounter:Number = 0;
		private var hardSwitchLimiter:Number = 0;
		private var hardSwitchCount:int = 0;

		CONFIG::LOGGING
		{
			private static const logger:Logger = Log.getLogger("org.osmf.net.httpstreaming.DownloadRatioRule");
		}
	}
}
