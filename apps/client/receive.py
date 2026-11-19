import argparse,json
from azure.identity import AzureCliCredential
from azure.servicebus import ServiceBusClient
p=argparse.ArgumentParser()
p.add_argument('--namespace', required=True)
p.add_argument('--limit',type=int,default=20)
a=p.parse_args()
with ServiceBusClient(fully_qualified_namespace=a.namespace+'.servicebus.windows.net', credential=AzureCliCredential()) as c:
    with c.get_queue_receiver(queue_name='ai-results',max_wait_time=10) as r:
        received=0
        while received<a.limit:
            batch=r.receive_messages(max_message_count=min(10,a.limit-received),max_wait_time=10)
            if not batch: break
            for msg in batch:
                result=json.loads(str(msg))
                print(json.dumps(result,ensure_ascii=False,indent=2))
                r.complete_message(msg)
                received+=1
print('Recibidos:',received)
