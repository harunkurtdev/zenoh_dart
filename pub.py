import time
import zenoh

# Zenoh oturumu başlat
conf = zenoh.Config()
conf.insert_json5("connect/endpoints", '["tcp/localhost:7447","tcp/localhost:7448"]')

session = zenoh.open(conf)

key_expr = "mqtt/demo/sensor/temperature"


def listener(sample):
    print(f"[Subscriber] {sample.key_expr}: {sample.payload.to_string()}")


# sub = session.declare_subscriber(key_expr, listener)

pub = session.declare_publisher(key_expr)

for i in range(5):
    msg = f"merhaba zenoh #{i+1}"
    print(f"[Publisher] Gönderiliyor: {msg}")
    pub.put(msg)
    time.sleep(1)

pub.undeclare()
# sub.undeclare()
session.close()