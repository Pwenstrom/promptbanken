import unittest

from server.catalog_renderer import render_template_variant


class CatalogRendererTests(unittest.TestCase):
    def test_renders_global_bindings_and_context_override(self):
        variant = {
            "prompt_text": "Skriv ett {{ton}} svar till {{malgrupp}}. Du är {{roll}} i {{kontext}}.",
            "parameter_schema": {
                "fields": [
                    {"key": "kontext", "source": "global"},
                    {"key": "roll", "source": "global"},
                    {"key": "malgrupp", "source": "global"},
                    {"key": "ton", "source": "global"},
                ]
            },
            "default_bindings": {
                "roll": "handläggare",
                "malgrupp": "invånare",
                "ton": "tydligt och vänligt",
            },
            "binding_overrides": [
                {"when": {"kontext": "företag"}, "set": {"malgrupp": "företagare"}}
            ],
        }

        rendered = render_template_variant(
            variant,
            {
                "kontext": "företag",
                "roll": "handläggare",
                "malgrupp": "invånare",
                "ton": "formellt",
            },
        )

        self.assertEqual(
            rendered,
            "Skriv ett formellt svar till företagare. Du är handläggare i företag.",
        )

    def test_legacy_input_marker_uses_supplied_input(self):
        variant = {
            "prompt_text": "Input:\n[]",
            "parameter_schema": {"legacy_fallback_field": "input", "fields": []},
            "default_bindings": {},
            "binding_overrides": [],
        }

        rendered = render_template_variant(variant, {"input": "Hej"})

        self.assertEqual(rendered, "Input:\nHej")


if __name__ == "__main__":
    unittest.main()
