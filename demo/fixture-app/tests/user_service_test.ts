import { createUser } from "../src/user_service";

describe("createUser", () => {
  it("creates a user", () => {
    expect(createUser("Ryan").id).toBe("ryan");
  });
});

export const TEST_ACTION_LABEL = "createUser";
