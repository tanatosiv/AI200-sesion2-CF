import json
import os
import signal
import time
from datetime import datetime, timezone
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from openai import OpenAI

running = True

def stop(*_):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

def run():
    namespace = os.environ['SERVICEBUS_NAMESPACE']
    incoming = os.getenv('REQUEST_QUEUE', 'ai-requests')
    outgoing = os.getenv('RESULT_QUEUE', 'ai-results')
    endpoint = os.environ['FOUNDRY_OPENAI_BASE_URL'].rstrip('/') + '/'
    deployment = os.environ['FOUNDRY_MODEL_DEPLOYMENT']
    credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    token_provider = get_bearer_token_provider(credential, 'https://cognitiveservices.azure.com/.default')
    llm = OpenAI(base_url=endpoint, api_key=token_provider, timeout=50, max_retries=1)
    print(f'Worker started. Queues={incoming}/{outgoing}', flush=True)
    with ServiceBusClient(fully_qualified_namespace=f'{namespace}.servicebus.windows.net', credential=credential) as bus:
        with bus.get_queue_receiver(queue_name=incoming, max_wait_time=10) as receiver, bus.get_queue_sender(queue_name=outgoing) as sender:
            while running:
                messages = receiver.receive_messages(max_message_count=1, max_wait_time=10)
                for message in messages:
                    job_id = None
                    try:
                        payload = json.loads(str(message))
                        job_id = str(payload['id'])
                        question = str(payload['question'])[:2000]
                        if not question.strip():
                            raise ValueError('Empty question')
                        response = llm.responses.create(model=deployment, instructions='Responde en español, de manera concisa a la pregunta técnica.', input=question, max_output_tokens=200)
                        record = {'id': job_id, 'question': question, 'answer': response.output_text, 'processed_at': datetime.now(timezone.utc).isoformat(), 'replica': os.getenv('HOSTNAME', 'unknown')}
                        sender.send_messages(ServiceBusMessage(json.dumps(record, ensure_ascii=False), message_id=job_id))
                        receiver.complete_message(message)
                        print('processed job=' + job_id, flush=True)
                    except Exception as exc:
                        print(f'ERROR job={job_id}: {type(exc).__name__}', flush=True)
                        # Service Bus reentrega y manda a DLQ si supera MaxDeliveryCount.
                        receiver.abandon_message(message)
                        time.sleep(1)

if __name__ == '__main__':
    run()
