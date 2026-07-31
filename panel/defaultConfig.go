package panel

import "github.com/XrayR-project/XrayR/service/controller"

func getDefaultLogConfig() *LogConfig {
	return &LogConfig{
		Level:      "none",
		AccessPath: "",
		ErrorPath:  "",
	}
}

func getDefaultConnectionConfig() *ConnectionConfig {
	return &ConnectionConfig{
		Handshake:    8,
		ConnIdle:     300,
		// Long one-way windows: speed-test uploads keep sending after the peer
		// half-closes downlink; UplinkOnly=5 cuts those tests mid-way.
		UplinkOnly:   300,
		DownlinkOnly: 300,
		BufferSize:   512,
	}
}

func getDefaultControllerConfig() *controller.Config {
	return &controller.Config{
		ListenIP:       "0.0.0.0",
		SendIP:         "0.0.0.0",
		UpdatePeriodic: 60,
		DNSType:        "AsIs",
	}
}
