"""The error every tool reports to the model."""


class ToolError(Exception):
    """A refused tool call, reported as `[<code>] <message>`.

    `code` is a stable `E_*` literal the tool descriptions and tests refer to.
    """

    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"[{code}] {message}")
        self.code = code
        self.message = message
