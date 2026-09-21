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


def chat_with_tools(
    *,
    system_prompt: str,
    messages: list[dict],
    tools: list[dict],
    handle_tool,
    model: str = DEFAULT_MODEL,
    max_tokens: int = 1500,
    max_tool_rounds: int = 3,
) -> str:
    """Run one chat turn, letting the model call tools, and return its final text.

    handle_tool(name, input) -> str runs a tool and returns the result text for the model.
    The system prompt is marked cacheable: it holds the athlete's profile and program,
    which is identical from one chat turn to the next.
    """
    system = [{"type": "text", "text": system_prompt, "cache_control": {"type": "ephemeral"}}]
    convo = list(messages)
    spoken: list[str] = []  # fallback: any text the model wrote, including before tool calls

    for _ in range(max_tool_rounds + 1):
        response = client.messages.create(
            model=model,
            max_tokens=max_tokens,
            system=system,
            messages=convo,
            tools=tools,
        )
        texts = [b.text.strip() for b in response.content if b.type == "text" and b.text.strip()]
        spoken += texts
        if response.stop_reason != "tool_use":
            # The reply is what the model says after its tools have run. Anything it wrote
            # before calling a tool is discarded so the athlete never sees it twice.
            return "\n\n".join(texts) or "\n\n".join(spoken)

        convo.append({"role": "assistant", "content": response.content})
        results: list[dict] = []
        for block in response.content:
            if block.type != "tool_use":
                continue
            try:
                output = handle_tool(block.name, block.input)
            except Exception as e:  # report to the model instead of failing the chat
                output = f"Tool error: {e}"
            results.append(
                {"type": "tool_result", "tool_use_id": block.id, "content": output}
            )
        results.append(
            {
                "type": "text",
                "text": (
                    "(Tool results are above. Text you wrote before calling tools is "
                    "discarded and the athlete has not seen it. Write your complete "
                    "reply to the athlete now, once.)"
                ),
            }
        )
        convo.append({"role": "user", "content": results})

    # Out of tool rounds: use whatever the model said; the caller supplies a fallback if empty.
    return "\n\n".join(spoken)
