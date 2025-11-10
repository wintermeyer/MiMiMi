# Mimimi

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? See [DEPLOYMENT.md](DEPLOYMENT.md) for our complete self-hosted deployment guide with hot code upgrade support.

## Deployment Features

This application includes a hybrid deployment system with:

- **Hot Code Upgrades**: Zero-downtime deployments (<1 second) for most changes
- **Automatic Fallback**: Intelligently switches to cold deploy when needed (migrations, supervision changes)
- **GitHub Actions Integration**: Automated deployment on push to `main`
- **Self-Hosted**: Complete guide for deploying to Debian Linux
- **Filesystem-Based**: No S3 or external storage required

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete setup instructions.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
