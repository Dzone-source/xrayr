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
		ConnIdle:     600,
		// Long one-way windows: speed-test uploads keep sending after the peer
		// half-closes downlink; small UplinkOnly cuts those tests mid-way.
		UplinkOnly:   3600,
		DownlinkOnly: 3600,
		BufferSize:   1024,
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
