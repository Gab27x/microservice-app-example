import time
import redis
import os
import json
import random

def log_message(message):
    time_delay = random.randrange(0, 2000)
    time.sleep(time_delay / 1000)
    print('message received after waiting for {}ms: {}'.format(time_delay, message))

if __name__ == '__main__':
    redis_host = os.environ.get('REDIS_HOST', 'redis-todo')
    redis_port = int(os.environ.get('REDIS_PORT', 6379))
    redis_channel = os.environ.get('REDIS_CHANNEL', 'log_channel')
    zipkin_url = os.environ.get('ZIPKIN_URL', 'http://zipkin:9411/api/v2/spans')
    
    print(f'Connecting to Redis at {redis_host}:{redis_port}')
    print(f'Subscribing to channel: {redis_channel}')
    
    try:
        pubsub = redis.Redis(host=redis_host, port=redis_port, db=0).pubsub()
        pubsub.subscribe([redis_channel])
        
        print('Waiting for messages...')
        for item in pubsub.listen():
            if item['type'] == 'message':
                try:
                    message = json.loads(str(item['data'].decode("utf-8")))
                    log_message(message)
                except Exception as e:
                    print(f'Error processing message: {e}')
                    continue
    except Exception as e:
        print(f'Error connecting to Redis: {e}')




