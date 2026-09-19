import json
from typing import TypeVar

from anthropic import Anthropic
from pydantic import BaseModel

from app.config import settings

client = Anthropic(api_key=settings.anthropic_api_key)

DEFAULT_MODEL = "claude-sonnet-5"

T = TypeVar("T", bound=BaseModel)


def generate_structured(
    *,
    system_prompt: str,
    user_message: str,
    response_schema: type[T],
    model: str = DEFAULT_MODEL,
    max_tokens: int = 4096,
) -> T:
    """Call Claude and force output matching response_schema via tool use."""
    tool_name = "emit_result"
    message = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        system=system_prompt,
        tools=[
            {
                "name": tool_name,
                "description": "Emit the structured result.",
                "input_schema": response_schema.model_json_schema(),
            }
        ],
        tool_choice={"type": "tool", "name": tool_name},
        messages=[{"role": "user", "content": user_message}],
    )

    for block in message.content:
        if block.type == "tool_use" and block.name == tool_name:
            return response_schema.model_validate(block.input)

    raise RuntimeError("Model did not return the expected tool call")
