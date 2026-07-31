package sspanel

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// FlexString unmarshals JSON string, number, or bool into a string.
// DPanel/SSPanel custom_config often sends offset_port_node as a number and
// allow_insecure as a bool; strict string fields caused XrayR to panic on start.
type FlexString string

func (f FlexString) String() string {
	return string(f)
}

func (f *FlexString) UnmarshalJSON(data []byte) error {
	data = bytes.TrimSpace(data)
	if len(data) == 0 || bytes.Equal(data, []byte("null")) {
		*f = ""
		return nil
	}

	switch data[0] {
	case '"':
		var s string
		if err := json.Unmarshal(data, &s); err != nil {
			return err
		}
		*f = FlexString(s)
		return nil
	case 't', 'f':
		var b bool
		if err := json.Unmarshal(data, &b); err != nil {
			return err
		}
		*f = FlexString(strconv.FormatBool(b))
		return nil
	default:
		// number (int or float)
		var n json.Number
		if err := json.Unmarshal(data, &n); err != nil {
			return fmt.Errorf("FlexString: unsupported JSON value %s: %w", string(data), err)
		}
		// Prefer integer form for ports ("443" not "443.0")
		if i, err := n.Int64(); err == nil {
			*f = FlexString(strconv.FormatInt(i, 10))
			return nil
		}
		if fv, err := n.Float64(); err == nil {
			if fv == float64(int64(fv)) {
				*f = FlexString(strconv.FormatInt(int64(fv), 10))
				return nil
			}
			*f = FlexString(strconv.FormatFloat(fv, 'f', -1, 64))
			return nil
		}
		*f = FlexString(n.String())
		return nil
	}
}

func (f FlexString) MarshalJSON() ([]byte, error) {
	return json.Marshal(string(f))
}

// FlexBool unmarshals JSON bool, number (0/1), or string ("true"/"1") into bool.
// DPanel sometimes stores enable_reality as 1 / "1".
type FlexBool bool

func (f FlexBool) Bool() bool {
	return bool(f)
}

func (f *FlexBool) UnmarshalJSON(data []byte) error {
	data = bytes.TrimSpace(data)
	if len(data) == 0 || bytes.Equal(data, []byte("null")) {
		*f = false
		return nil
	}
	switch data[0] {
	case 't', 'f':
		var b bool
		if err := json.Unmarshal(data, &b); err != nil {
			return err
		}
		*f = FlexBool(b)
		return nil
	case '"':
		var s string
		if err := json.Unmarshal(data, &s); err != nil {
			return err
		}
		switch strings.ToLower(strings.TrimSpace(s)) {
		case "1", "true", "yes", "on":
			*f = true
		default:
			*f = false
		}
		return nil
	default:
		var n json.Number
		if err := json.Unmarshal(data, &n); err != nil {
			return fmt.Errorf("FlexBool: unsupported JSON value %s: %w", string(data), err)
		}
		i, err := n.Int64()
		if err != nil {
			return err
		}
		*f = FlexBool(i != 0)
		return nil
	}
}

func (f FlexBool) MarshalJSON() ([]byte, error) {
	return json.Marshal(bool(f))
}
