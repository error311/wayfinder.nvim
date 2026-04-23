import { createUser, updateUser } from "../src/user_service";

describe("user flow", () => {
  it("renames a draft", () => {
    const draft = createUser("Morgan");
    expect(updateUser(draft.id, "Moe").name).toBe("Moe");
  });
});
