# oidc.tf — GitHub OIDC identity provider (CENTRAL account, default provider)
#
# Registers GitHub Actions' OIDC issuer so AWS will trust tokens it mints.
# Created once per account that the pipeline authenticates into directly.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"] # the token "audience" (aud claim)

  # thumbprint_list is intentionally omitted: AWS no longer validates it for GitHub
  # (it trusts GitHub's provider via a CA), and AWS provider ~> 5.x makes it optional.
  # If your provider version complains, supply GitHub's CURRENT root CA thumbprint
  # (look it up — do not hardcode a stale value).
}
