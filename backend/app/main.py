from __future__ import annotations

import logging
import os
import uuid
from pathlib import Path
from typing import AsyncIterator

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from .llm_clients import OllamaGateway
from .prompt_repository import PromptRepository
from .schemas import ChatStreamRequest, ModelInfo, ModelsResponse, ProviderInfo, ProvidersResponse, RunRequest, RunResponse

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)
logger = logging.getLogger("promptbanken.gateway")

app = FastAPI(title="Promptbanken Community LLM Gateway", version="0.4.0")

_default_allowed_origins = "http://localhost:8080,http://127.0.0.1:8080"
allowed_origins = [
    origin.strip()
    for origin in os.getenv("ALLOWED_ORIGINS", _default_allowed_origins).split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

repo_root = Path(__file__).resolve().parents[2]
prompt_repository = PromptRepository(repo_root=repo_root)
ollama_gateway = OllamaGateway()


def build_final_prompt(prompt_text: str, user_input: str) -> str:
    return (
        "System/Instruktion:\n"
        f"{prompt_text.strip()}\n\n"
        "Användarens indata:\n"
        f"{user_input.strip()}"
    )


def _http_error_to_detail(exc: httpx.HTTPError, request_id: str) -> dict[str, str | int | None]:
    request_url = str(exc.request.url) if exc.request else "unknown"
    request_method = exc.request.method if exc.request else "UNKNOWN"
    status_code: int | None = None
    body_excerpt: str | None = None

    if isinstance(exc, httpx.HTTPStatusError):
        status_code = exc.response.status_code
        body_excerpt = exc.response.text[:500]

    logger.error(
        "Ollama request failed request_id=%s method=%s url=%s status=%s error=%r body_excerpt=%r",
        request_id,
        request_method,
        request_url,
        status_code,
        exc,
        body_excerpt,
    )

    return {
        "message": "Kunde inte köra modell via Ollama.",
        "request_id": request_id,
        "upstream_status": status_code,
        "upstream_body_excerpt": body_excerpt,
        "error_type": exc.__class__.__name__,
    }




@app.get("/api/providers", response_model=ProvidersResponse)
async def get_providers() -> ProvidersResponse:
    return ProvidersResponse(providers=[ProviderInfo(name="ollama")])

@app.get("/api/models", response_model=ModelsResponse)
async def get_models() -> ModelsResponse:
    request_id = str(uuid.uuid4())

    try:
        models = await ollama_gateway.get_client().list_models()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=_http_error_to_detail(exc, request_id)) from exc

    return ModelsResponse(models=[ModelInfo(name=model) for model in models])


@app.post("/api/run", response_model=RunResponse)
async def run_prompt(request: RunRequest) -> RunResponse:
    request_id = str(uuid.uuid4())

    try:
        prompt_text = request.prompt_text or prompt_repository.get_prompt_text(request.prompt_id or "")
    except (KeyError, FileNotFoundError) as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    final_prompt = build_final_prompt(prompt_text=prompt_text, user_input=request.user_input)

    try:
        answer = await ollama_gateway.get_client().run_chat(model=request.model, final_prompt=final_prompt)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=_http_error_to_detail(exc, request_id)) from exc

    logger.info("Prompt run success request_id=%s model=%s prompt_id=%s", request_id, request.model, request.prompt_id)
    return RunResponse(model=request.model, provider="ollama", prompt_used=final_prompt, response=answer)




@app.post("/api/chat/stream")
async def run_chat_stream(request: ChatStreamRequest, http_request: Request) -> StreamingResponse:
    request_id = str(uuid.uuid4())

    async def event_stream() -> AsyncIterator[str]:
        try:
            async for chunk in ollama_gateway.get_client().run_chat_stream_messages(
                model=request.model,
                messages=[{"role": message.role, "content": message.content} for message in request.messages],
                should_abort=http_request.is_disconnected,
            ):
                yield chunk
            logger.info("Chat stream finished request_id=%s model=%s", request_id, request.model)
        except httpx.HTTPError as exc:
            error_detail = _http_error_to_detail(exc, request_id)
            logger.error("Chat stream failed detail=%s", error_detail)
            raise

    return StreamingResponse(event_stream(), media_type="text/plain; charset=utf-8")


@app.post("/api/run/stream")
async def run_prompt_stream(request: RunRequest, http_request: Request) -> StreamingResponse:
    request_id = str(uuid.uuid4())

    try:
        prompt_text = request.prompt_text or prompt_repository.get_prompt_text(request.prompt_id or "")
    except (KeyError, FileNotFoundError) as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc

    final_prompt = build_final_prompt(prompt_text=prompt_text, user_input=request.user_input)

    async def event_stream() -> AsyncIterator[str]:
        try:
            async for chunk in ollama_gateway.get_client().run_chat_stream(
                model=request.model,
                final_prompt=final_prompt,
                should_abort=http_request.is_disconnected,
            ):
                yield chunk
            logger.info("Prompt stream finished request_id=%s model=%s prompt_id=%s", request_id, request.model, request.prompt_id)
        except httpx.HTTPError as exc:
            error_detail = _http_error_to_detail(exc, request_id)
            logger.error("Prompt stream failed detail=%s", error_detail)
            raise

    return StreamingResponse(event_stream(), media_type="text/plain; charset=utf-8")
