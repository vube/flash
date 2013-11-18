package
{
	import org.flowplayer.httpstreaming.HttpStreamingProvider;
	import org.flowplayer.f4m.F4mProvider;
	import org.flowplayer.bwcheck.BwCheckProvider;
	import org.flowplayer.controls.Controls;
    
	public class BuiltInConfig {
		private var httpstreaming:org.flowplayer.httpstreaming.HttpStreamingProvider;
		private var f4m:org.flowplayer.f4m.F4mProvider;
		private var bwcheck:org.flowplayer.bwcheck.BwCheckProvider;
		private var controls:org.flowplayer.controls.Controls;

		public static const config:Object = { 
			"plugins": {
				"httpstreaming": {
					"url": 'org.flowplayer.httpstreaming.HttpStreamingProvider'
				},
				"f4m": {
					"url": 'org.flowplayer.f4m.F4mProvider'
				},
				"bwcheck": {
					"url": 'org.flowplayer.bwcheck.BwCheckProvider'
				},
				"controls": {
					"url": 'org.flowplayer.controls.Controls'
				}
			}
		}
	}; 
}
