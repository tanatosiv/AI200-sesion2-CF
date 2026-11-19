import os
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi import Request
from pydantic import BaseModel, Field
from openai import OpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

app = FastAPI(title='AI-200 Foundry Chat', version='1.0')
templates = Jinja2Templates(directory='templates')

class ChatRequest(BaseModel):
    question: str = Field(min_length=1, max_length=2000)

def ask_model(question: str) -> str:
    endpoint = os.environ.get('FOUNDRY_OPENAI_BASE_URL', '').strip()
    deployment = os.environ.get('FOUNDRY_MODEL_DEPLOYMENT', '').strip()
    if not endpoint or not deployment:
        raise RuntimeError('Configure FOUNDRY_OPENAI_BASE_URL y FOUNDRY_MODEL_DEPLOYMENT.')
    credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
    provider = get_bearer_token_provider(credential, 'https://cognitiveservices.azure.com/.default')
    client = OpenAI(base_url=endpoint.rstrip('/') + '/', api_key=provider, timeout=45.0, max_retries=1)
    response = client.responses.create(
        model=deployment,
        instructions='Eres un asistente técnico sobre Azure para estudiantes de AI-200. Responde en español, de forma clara y precisa. No inventes referencias.',
        input=question,
        max_output_tokens=350,
    )
    return response.output_text or '(El modelo no devolvió texto.)'

@app.get('/health')
def health():
    return {'status': 'ok', 'edition': os.environ.get('APP_EDITION', 'v1')}

@app.get('/config')
def config():
    return {'edition': os.environ.get('APP_EDITION', 'v1'), 'model_configured': bool(os.getenv('FOUNDRY_MODEL_DEPLOYMENT')), 'secret_configured': bool(os.getenv('LAB_DEMO_SECRET'))}

@app.get('/', response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse('index.html', {'request': request, 'edition': os.getenv('APP_EDITION','v1')})

@app.post('/api/chat')
def chat(payload: ChatRequest):
    try:
        return {'answer': ask_model(payload.question), 'edition': os.environ.get('APP_EDITION', 'v1')}
    except Exception as exc:
        # No exponer tokens, endpoints ni trazas al navegador.
        print(f'ERROR calling model: {type(exc).__name__}', flush=True)
        raise HTTPException(status_code=502, detail='Falló la consulta a Microsoft Foundry. Revisa los logs y los permisos RBAC.') from None
