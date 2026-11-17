package sspanel

import (
	"encoding/json"
	"fmt"
)

// NodeInfoResponse is the response of node
type NodeInfoResponse struct {
	Group           int             `json:"node_group"`
	Class           int             `json:"node_class"`
	SpeedLimit      float64         `json:"node_speedlimit"`
	TrafficRate     float64         `json:"traffic_rate"`
	Sort            int             `json:"sort"`
	RawServerString string          `json:"server"`
	Type            string          `json:"type"`
	CustomConfig    json.RawMessage `json:"custom_config"`
	Version         string          `json:"version"`
}

type CustomConfig struct {
	OffsetPortNode string          `json:"offset_port_node"`
	Host           string          `json:"host"`
	Method         string          `json:"method"`
	TLS            string          `json:"tls"`
	EnableVless    string          `json:"enable_vless"`
	Network        string          `json:"network"`
	Security       string          `json:"security"`
	Path           string          `json:"path"`
	VerifyCert     bool            `json:"verify_cert"`
	Obfs           string          `json:"obfs"`
	Header         json.RawMessage `json:"header"`
	AllowInsecure  string          `json:"allow_insecure"`
	Servicename    string          `json:"servicename"`
	EnableXtls     string          `json:"enable_xtls"`
	Flow           string          `json:"flow"`
	EnableREALITY  bool            `json:"enable_reality"`
	RealityOpts    *REALITYConfig  `json:"reality-opts"`
}

// UnmarshalJSON accepts scalar representations used by SSPanel-compatible panels.
// Calendar-version SSPanel uses strings; DPanel also sends numbers and booleans.
func (c *CustomConfig) UnmarshalJSON(data []byte) error {
	type plain CustomConfig
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	for _, name := range []string{"offset_port_node", "enable_vless", "allow_insecure", "enable_xtls", "tls"} {
		raw, ok := fields[name]
		if !ok || string(raw) == "null" {
			continue
		}
		var text string
		if json.Unmarshal(raw, &text) == nil {
			continue
		}
		var value any
		if err := json.Unmarshal(raw, &value); err != nil {
			return err
		}
		switch v := value.(type) {
		case bool:
			if name == "offset_port_node" {
				return fmt.Errorf("custom_config.%s must be an integer or string", name)
			}
			if v {
				text = "1"
			} else {
				text = "0"
			}
		case float64:
			if v != float64(int64(v)) {
				return fmt.Errorf("custom_config.%s must be integral", name)
			}
			text = fmt.Sprintf("%.0f", v)
		default:
			return fmt.Errorf("custom_config.%s has an invalid scalar type", name)
		}
		fields[name], _ = json.Marshal(text)
	}
	normalized, err := json.Marshal(fields)
	if err != nil {
		return err
	}
	var result plain
	if err := json.Unmarshal(normalized, &result); err != nil {
		return err
	}
	*c = CustomConfig(result)
	return nil
}

// UserResponse is the response of user
type UserResponse struct {
	ID          int     `json:"id"`
	Passwd      string  `json:"passwd"`
	Port        uint32  `json:"port"`
	Method      string  `json:"method"`
	SpeedLimit  float64 `json:"node_speedlimit"`
	DeviceLimit int     `json:"node_iplimit"`
	UUID        string  `json:"uuid"`
	AliveIP     int     `json:"alive_ip"`
}

// Response is the common response
type Response struct {
	Ret  uint            `json:"ret"`
	Data json.RawMessage `json:"data"`
}

// PostData is the data structure of post data
type PostData struct {
	Data interface{} `json:"data"`
}

// SystemLoad is the data structure of system load
type SystemLoad struct {
	Uptime string `json:"uptime"`
	Load   string `json:"load"`
}

// OnlineUser is the data structure of online user
type OnlineUser struct {
	UID int    `json:"user_id"`
	IP  string `json:"ip"`
}

// UserTraffic is the data structure of traffic
type UserTraffic struct {
	UID      int   `json:"user_id"`
	Upload   int64 `json:"u"`
	Download int64 `json:"d"`
}

type RuleItem struct {
	ID      int    `json:"id"`
	Content string `json:"regex"`
}

type IllegalItem struct {
	ID  int `json:"list_id"`
	UID int `json:"user_id"`
}

type REALITYConfig struct {
	Dest             string   `json:"dest,omitempty"`
	ProxyProtocolVer uint64   `json:"proxy_protocol_ver,omitempty"`
	ServerNames      []string `json:"server_names,omitempty"`
	PrivateKey       string   `json:"private_key,omitempty"`
	MinClientVer     string   `json:"min_client_ver,omitempty"`
	MaxClientVer     string   `json:"max_client_ver,omitempty"`
	MaxTimeDiff      uint64   `json:"max_time_diff,omitempty"`
	ShortIds         []string `json:"short_ids,omitempty"`
}
