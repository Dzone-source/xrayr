package sspanel

import (
	"encoding/json"
	"testing"
)

func TestCustomConfigScalarTypes(t *testing.T) {
	for _, input := range []string{
		`{"offset_port_node":"443","enable_vless":"1","enable_xtls":"0","allow_insecure":"0","enable_reality":true,"verify_cert":false}`,
		`{"offset_port_node":443,"enable_vless":true,"enable_xtls":false,"allow_insecure":false,"enable_reality":true,"verify_cert":false}`,
		`{"offset_port_node":443,"enable_vless":1,"enable_xtls":0,"allow_insecure":0,"enable_reality":"true","verify_cert":"0"}`,
	} {
		var c CustomConfig
		if err := json.Unmarshal([]byte(input), &c); err != nil {
			t.Fatal(err)
		}
		if c.OffsetPortNode != "443" || c.EnableVless != "1" || c.EnableXtls != "0" || c.AllowInsecure != "0" || !c.EnableREALITY || c.VerifyCert {
			t.Fatalf("scalar normalization changed config: %+v", c)
		}
	}
	for _, input := range []string{
		`{"offset_port_node":true}`, `{"offset_port_node":443.5}`, `{"offset_port_node":-1}`,
		`{"offset_port_node":65536}`, `{"enable_vless":{}}`, `{"enable_vless":2}`,
		`{"enable_reality":"invalid"}`, `{"allow_insecure":[]}`,
	} {
		var c CustomConfig
		if err := json.Unmarshal([]byte(input), &c); err == nil {
			t.Errorf("expected validation error for %s", input)
		}
	}
}
