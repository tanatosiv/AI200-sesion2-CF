import argparse, json, uuid
from azure.identity import AzureCliCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
p = argparse.ArgumentParser()
p.add_argument('--namespace', required=True)
p.add_argument('--count', type=int, default=20)
p.add_argument('--question', default='Explica una ventaja de Azure Container Apps para aplicaciones de IA.')
a=p.parse_args()
if not 1<=a.count<=500: p.error('--count debe estar entre 1 y 500')
with ServiceBusClient(fully_qualified_namespace=a.namespace+'.servicebus.windows.net', credential=AzureCliCredential()) as c:
    with c.get_queue_sender(queue_name='ai-requests') as sender:
        for i in range(a.count):
            job={'id':str(uuid.uuid4()),'question':f'{a.question} Caso {i+1}.'}
            sender.send_messages(ServiceBusMessage(json.dumps(job,ensure_ascii=False),message_id=job['id']))
            print('Enviado:',job['id'])
