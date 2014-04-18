/***** Constants and classes for interacting with SkyNet.im *****/
const SKYNET_BASE = "http://skynet.im";
const SKYNET_DEVICES = "devices";
const SKYNET_DATA = "data";
const SKYNET_STATUS = "status";
const SKYNET_AUTH = "authenticate"

class SkyNetDevice {
    _properties = null;
    
    // streaming
    _onDataCallback = null;
    _streamingRequest = null;
    
    constructor(properties, token = null) {
        _properties = properties
        if (token != null && !("token" in _properties)) _properties["token"] <- token;
    }
    
    function serialize() {
        return http.jsonencode(_properties);
    }
    
    function UpdateProperties(properties) {
        local url = format("%s/%s/%s", SKYNET_BASE, SKYNET_DEVICES, _properties.uuid);
        local headers = { "Content-Type": "application/json" };
        
        local resp = http.put(url, headers, http.jsonencode(properties)).sendsync();
        if (resp.statuscode != 200) {
            server.log(format("ERROR: Could not update device (%s) - %s", resp.statuscode.tostring(), resp.body));
            return;
        }
        
        local data = http.jsondecode(resp.body);
        if ("error" in data) {
            server.log(format("ERROR: Could not update device - %s", data.error.message));
            return;
        }
        
        // if everything worked, update properties
        foreach(k,v in data) {
            if (v == null) {
                if (k in _properties) delete _properties[k];
            } else {
                if (k in _properties) _properties[k] = v;
                else _properties[k] <- v;
            }
        }
    }
    
    function GetData() {
        local url = format("%s/%s/%s?token=%s", SKYNET_BASE, SKYNET_DATA, _properties.uuid, _properties.token);
        local resp = http.get(url).sendsync();
        
        if (resp.statuscode != 200) {
            server.log(format("ERROR: Could not get data (%s) - %s", resp.statuscode.tostring(), resp.body));
            return null;
        }
        
        local data = http.jsondecode(resp.body);
        if ("error" in data) {
            server.log(format("ERROR: Could not get data. %s", data.error.message));
            return null;
        }

        return data;
    }
    
    function Push(data) {
        local url = format("%s/%s/%s?token=%s", SKYNET_BASE, SKYNET_DATA, _properties.uuid, _properties.token);
        local headers = { "Content-Type": "application/json" };
        
        local resp = http.post(url, headers, http.jsonencode(data)).sendsync();
        if (resp.statuscode != 200) {
            server.log(format("ERROR: Could not post data (%s) - %s", resp.statuscode.tostring(), resp.body));
            return;
        }
        
        local data = http.jsondecode(resp.body);
        if ("error" in data) {
            server.log(format("ERROR: Could not post data - %s", data.error.message));
            return;
        }

    }
    
    function onData(cb) {
        _onDataCallback = cb;
    }
    
    function StreamData(autoReconnect = true) {
        if (_streamingRequest != null) {
            _streamingRequest.cancel();
            _streamingRequest = null;
        }
        
        local url = format("%s/%s/%s?token=%s&stream=true", SKYNET_BASE, SKYNET_DATA, _properties.uuid, _properties.token);
        server.log("Opening stream..");
        _streamingRequest = http.get(url).sendasync(function(resp) {
            server.log(format("Stream closed (%s - %s)", resp.statuscode.tostring(), resp.body));
            if (autoReconnect) {
                StreamData(true);
            }
        }.bindenv(this), function(data) {
            if (_onDataCallback) {
                try {
                    local d = http.jsondecode(data);
                    _onDataCallback(d);
                } catch (ex) {
                    server.log("Error in onData callback: " + ex);
                    server.log("data=" + data);
                }
            }
        }.bindenv(this));
    }
}

class SkyNet {
    _token = null;
    
    constructor (token) {
        this._token = token;
    }
    
    function GetStatus() {
        local statusUrl = format("%s/%s", SKYNET_BASE, SKYNET_STATUS);
        local resp = http.get(statusUrl).sendsync();
        if (resp.statuscode != 200) {
            server.log("ERROR: Could not get system status (%s) - %s", resp.statuscode, resp.body);
            return false;
        } else {
            local data = http.jsondecode(resp.body);
            return ("skynet" in data && data.skynet == "online");
        }
    }
    
    function CreateDevice(properties) {
        if (!("token" in properties)) properties["token"] <- _token;
        
        // set some default properties
        if (!("platform" in properties)) properties["platform"] <- "electric imp";
        
        local url = format("%s/%s", SKYNET_BASE, SKYNET_DEVICES);
        
        local resp = http.post(url, {}, http.urlencode(properties)).sendsync();
        if (resp.statuscode == 200) {
            local p = http.jsondecode(resp.body);
            return SkyNetDevice(p);
        } 
        
        server.log(format("ERROR: Could not create device (%s) - %s", resp.statuscode.tostring(), resp.body));
        return null;
    }
    
    function GetDevice(uuid, token = null) {
        if (token == null) token = _token;
        local authUrl = format("%s/%s/%s?token=%s", SKYNET_BASE, SKYNET_AUTH, uuid, token);
        local deviceUrl = format("%s/%s/%s?token=%s", SKYNET_BASE, SKYNET_DEVICES, uuid, token);
        
        server.log(authUrl);
        
        local authResp = http.get(authUrl).sendsync();
        if (authResp.statuscode != 200) {
            server.log(format("ERROR: Could not authenticate device (%s) - %s", authResp.statuscode.tostring(), authResp.body));
            return null;
        }        
        
        local authData = http.jsondecode(authResp.body);
        if (!("authentication" in authData) || !authData.authentication) {
            server.log(format("ERROR: Could not authentice device. Invalid token."));
            return null;
        }
        
        local deviceResp = http.get(deviceUrl).sendsync();
        if (deviceResp.statuscode != 200) {
            server.log(format("ERROR: Could not get device (%s) - %s", deviceResp.statuscode.tostring(), deviceResp.body));
            return null;
        }
        
        local deviceData = http.jsondecode(deviceResp.body);
        if ("error" in deviceData) {
            server.log(format("ERROR: Could not get device. %s", deviceData.error.message));
            return  null;
        }

        return SkyNetDevice(deviceData, token);
    }
    
    function DeleteDevice(uuid, token = null) {
        if (token == null) token = _token;
        local deleteUrl = format("%s/%s/%s?token=%s", SKYNET_BASE, SKYNET_DEVICES, uuid, token);
        local resp = http.httpdelete(deleteUrl).sendsync();
        server.log(resp.statuscode +": " + resp.body);
    }
}


/***** Your code should go below this line *****/
const DEVICEID = "abc123matt";
const TOKEN = "this%20is%20my%20secret%20key";

// creat skynet object
skynet <- SkyNet(TOKEN);

// try to grab this device
device <- skynet.GetDevice(DEVICEID);

// if it doesn't exist, create it
if (device == null) {
    device = skynet.CreateDevice({
        uuid = DEVICEID,
        token = TOKEN,
        platform = "electric imp",
        lat = 37.39677,
        long = -122.10475
    });
    server.log(device.serialize());
}

// setup streaming
device.onData(function(data){ 
    server.log(http.jsonencode(data));
});

// start the stream
device.StreamData(true);    //auto-reconnect

//push some random data every 10 seconds
function loop() {
    imp.wakeup(10.0, loop);
    device.Push({ r = math.rand() % 100 });
} loop();


