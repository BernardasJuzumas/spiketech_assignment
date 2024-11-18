import requests
import time
import random
import string
import os
from questdb.ingress import Sender, TimestampNanos

# Settings
ping_interval = float(os.getenv('PING__INTERVAL', '0.2'))

def generate_random_string(length=10):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_slots():
    return random.sample(['P', 'R', 'Q'], random.randint(0, 3))

def send_request():
    base_url = "http://nginx/rpc/add_widget"
    widget_sn = generate_random_string()
    slots = generate_slots()
    payload = {
        "widget_sn": widget_sn,
        "widget_name": widget_sn,
        "slots": slots
    }

    start_time = time.time()
    response = requests.post(base_url, json=payload)
    end_time = time.time()

    response_time = end_time - start_time
    response_status = response.status_code
    print(f"Request took {response_time:.3f} seconds with status code {response_status}")

    VICTORIA_METRICS_URL = "http://victoria:8428/api/v1/import/prometheus"
    # Prepare data in Prometheus format
    # metric_name = "request_times"
    # labels = 'duration'
    timestamp = int(time.time())  # Current timestamp in milliseconds

    #data = f'{metric_name}{{{labels}}} {value} {timestamp}\n'
    data = 'request_times{label="duration"} '+str(response_time)+' '+str(timestamp)+'\n'
    print(data)


    response = requests.post(VICTORIA_METRICS_URL, data=data)

    if response.status_code == 204:
        print("Data sent successfully!")
    else:
        print(f"Failed to send data: {response.text}")

if __name__ == "__main__":
    while True:
        send_request()
        #time.sleep(ping_interval)
