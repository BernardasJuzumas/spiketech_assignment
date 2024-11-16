import requests
import time
import random
import string
import os
from influxdb_client import InfluxDBClient, Point

# Settings
ping_interval = float(os.getenv('PING__INTERVAL', '0.1'))


# InfluxDB client
influx_url = os.getenv('INFLUXDB_URL', 'http://localhost:8086')
influx_token = os.getenv('INFLUXDB_TOKEN', 'my-influxdb-token')
influx_org = os.getenv('INFLUXDB_ORG', 'my-org')
influx_bucket = os.getenv('INFLUXDB_BUCKET', 'my-bucket')

client = InfluxDBClient(url=influx_url, token=influx_token, org=influx_org)
write_api = client.write_api()


def generate_random_string(length=10):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_slots():
    return random.sample(['P', 'R', 'Q'], random.randint(0, 3))

def send_request():
    base_url = "http://nginx/rpc/add_widget"
    widget_sn = generate_random_string()
    widget_name = widget_sn
    slots = generate_slots()
    payload = {
        "widget_sn": widget_sn,
        "widget_name": widget_name,
        "slots": slots
    }

    start_time = time.time()
    response = requests.post(base_url, json=payload)
    end_time = time.time()

    response_time = end_time - start_time
    print(f"Request took {response_time} seconds")

    point = Point("request_times").field("duration", response_time)
    write_api.write(bucket=influx_bucket, org=influx_org, record=point)

if __name__ == "__main__":
    while True:
        send_request()
        time.sleep(ping_interval)