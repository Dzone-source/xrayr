package sspanel

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
)

// UnmarshalJSON accepts both legacy string scalars and typed JSON scalars used
// by newer panels, while keeping CustomConfig's existing public field types.
func (c *CustomConfig) UnmarshalJSON(data []byte) error {
	type plain CustomConfig
	var decoded plain
	wire := struct {
		*plain
		OffsetPortNode json.RawMessage `json:"offset_port_node"`
		EnableVless    json.RawMessage `json:"enable_vless"`
		EnableXtls     json.RawMessage `json:"enable_xtls"`
		AllowInsecure  json.RawMessage `json:"allow_insecure"`
		EnableREALITY  json.RawMessage `json:"enable_reality"`
		VerifyCert     json.RawMessage `json:"verify_cert"`
	}{plain: &decoded}
	if err := json.Unmarshal(data, &wire); err != nil {
		return err
	}
	port := bytes.TrimSpace(wire.OffsetPortNode)
	if len(port) > 0 && string(port) != "null" {
		if port[0] == '"' {
			if err := json.Unmarshal(port, &decoded.OffsetPortNode); err != nil {
				return fmt.Errorf("invalid offset_port_node string")
			}
		} else {
			if _, err := strconv.ParseUint(string(port), 10, 16); err != nil {
				return fmt.Errorf("offset_port_node must be a port number or string")
			}
			decoded.OffsetPortNode = string(port)
		}
	}
	for _, field := range []struct {
		name string
		raw  json.RawMessage
		dest *string
	}{
		{"enable_vless", wire.EnableVless, &decoded.EnableVless},
		{"enable_xtls", wire.EnableXtls, &decoded.EnableXtls},
		{"allow_insecure", wire.AllowInsecure, &decoded.AllowInsecure},
	} {
		value, err := configFlag(field.raw)
		if err != nil {
			return fmt.Errorf("invalid %s: %w", field.name, err)
		}
		*field.dest = value
	}
	for _, field := range []struct {
		name string
		raw  json.RawMessage
		dest *bool
	}{
		{"enable_reality", wire.EnableREALITY, &decoded.EnableREALITY},
		{"verify_cert", wire.VerifyCert, &decoded.VerifyCert},
	} {
		value, err := configFlag(field.raw)
		if err != nil {
			return fmt.Errorf("invalid %s: %w", field.name, err)
		}
		*field.dest = value == "1"
	}
	*c = CustomConfig(decoded)
	return nil
}

func configFlag(raw json.RawMessage) (string, error) {
	value := string(bytes.TrimSpace(raw))
	if value == "" || value == "null" {
		return "", nil
	}
	if value[0] == '"' {
		if err := json.Unmarshal(raw, &value); err != nil {
			return "", fmt.Errorf("expected boolean, 0/1, or equivalent string")
		}
	}
	switch value {
	case "", "0", "false":
		return "0", nil
	case "1", "true":
		return "1", nil
	default:
		return "", fmt.Errorf("expected boolean, 0/1, or equivalent string")
	}
}
