import requests
import time
import random
import string
import os
from questdb.ingress import Sender, TimestampNanos

# Settings
ping_interval = float(os.getenv('PING__INTERVAL', '0.1'))

# QuestDB ingestion endpoint
#ingest_url = f"{questdb_url}/imp"

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
    print(f"Request took {response_time:.3f} seconds")

    # Format data in InfluxDB line protocol
    line = f"request_times::duration={response_time:.6f}"

    # Write to QuestDB
    conf = f'http::addr=questdb:9000;'
    with Sender.from_conf(conf) as sender:
        sender.row(
            'request_times',
            columns={'duration': response_time},
            at=TimestampNanos.now()
            )

if __name__ == "__main__":
    while True:
        send_request()
        time.sleep(ping_interval)
