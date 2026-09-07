import { describe, expect, test } from "bun:test";
import { withoutUserInfo } from "../src/agents/profile-store";

/*
 * A credential hiding in a base URL, at the boundary that publishes to every surface.
 *
 * `openai-compatible` takes a base URL, and `https://user:secret@host/v1` is how several gateways
 * document themselves — so a stored selection can carry a password in a field that is not the key
 * field, and `publishableSelection` was stripping only `apiKey`. The Mac app refuses to save one
 * now, but a row written by an older app or edited by hand still arrives here, and this is where the
 * promise is made: the surface learns the address and the model, never the secret.
 */
describe("stripping a credential out of a published address", () => {
  test("removes a username and password", () => {
    expect(
      withoutUserInfo("https://user:secret@gateway.example.com/v1"),
    ).not.toContain("secret");
    expect(
      withoutUserInfo("https://user:secret@gateway.example.com/v1"),
    ).not.toContain("user");
    expect(
      withoutUserInfo("https://user:secret@gateway.example.com/v1"),
    ).toContain("gateway.example.com");
  });

  test("removes a bare token used as a username", () => {
    expect(
      withoutUserInfo("https://tok_live_abc@gateway.example.com/v1"),
    ).not.toContain("tok_live");
  });

  /// The ordinary case must survive untouched — including the port and path the endpoint needs.
  test("leaves an address with no credential exactly as it was", () => {
    for (const address of [
      "https://openrouter.ai/api/v1",
      "http://localhost:11434/v1",
      "http://host.docker.internal:11434/v1",
    ]) {
      expect(withoutUserInfo(address)).toBe(address);
    }
  });

  /// Nothing to strip and no claim to make about it, so it is handed back rather than mangled.
  test("leaves something that is not a URL alone", () => {
    expect(withoutUserInfo("not a url")).toBe("not a url");
    expect(withoutUserInfo("")).toBe("");
  });
});
