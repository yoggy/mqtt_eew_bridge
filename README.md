mqtt_eew_bridge
====
simple eew -> MQTT bridge

How to use
----

	$ git clone https://github.com/yoggy/mqtt_eew_bridge.git
    $ cd mqtt_eew_bridge
    $ sudo gem install eew_parser
    $ sudo gem install mqtt
    $ sudo gem install pit
    $ EDITOR=vim ./mqtt_eew_bridge.rb

        ---
        wni_user: username
        wni_pass: password
        mqtt_host: mqtt.example.com
        mqtt_port: 1883
        mqtt_user: mqtt_username
        mqtt_pass: mqtt_password
        mqtt_topic: topic

message type
----
    keepalive
        {"type":"keepalive"}
    
    eew
        {"type":"eew", "eew":"....."}

