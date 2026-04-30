# Geo Ip Wifi

### Basic IP geolocation (original behavior)

python geo_ip_wifi.py

### IP geolocation + WiFi positioning (best accuracy)

sudo python geo_ip_wifi.py --setup
sudo python geo_ip_wifi.py --scan-only
sudo python geo_ip_wifi.py --wifi

### WiFi positioning only

sudo python geo_ip_wifi.py --wifi-only

### Specify a particular wireless interface

sudo python geo_ip_wifi.py --wifi --interface wlp3s0

### Geolocate a specific IP + your WiFi location

sudo python geo_ip_wifi.py 8.8.8.8 --wifi
