# Contributing to TalkSense

First off, thank you for considering contributing to TalkSense!

## Code of Conduct

This project follows the principle of respect and professionalism. Please be kind and constructive.

## How Can I Contribute?

### Reporting Bugs

- Use GitHub Issues
- Include detailed description
- Provide steps to reproduce
- Specify environment (Azure region, Fabric capacity, etc.)

### Suggesting Enhancements

- Use GitHub Issues with [Feature Request] tag
- Clearly describe the use case
- Explain how it benefits the community

### Pull Requests

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly (especially IaC changes)
5. Update documentation
6. Commit with clear messages
7. Push and open a PR

### Documentation Improvements

Documentation is as important as code! Feel free to:
- Fix typos
- Clarify confusing sections
- Add examples
- Translate (if multilingual support is added)

## Development Guidelines

### Infrastructure as Code (IaC)

- **Bicep**: Follow Azure best practices
- **Terraform**: Use Azure Verified Modules when possible
- Test deployments in a dev environment
- Document parameters clearly

### Python (Data Generator)

- Follow PEP 8 style guide
- Add type hints
- Write docstrings
- Include examples

### Documentation

- Use Markdown
- Include code examples
- Keep mermaid diagrams up-to-date
- Link related documents

### Power BI

- Document DAX measures clearly
- Follow naming conventions
- Include comments in complex formulas
- Test with synthetic data

## Testing Checklist

Before submitting:

- [ ] IaC deploys successfully
- [ ] Synthetic data generator runs without errors
- [ ] Documentation is clear and accurate
- [ ] No sensitive data included
- [ ] .gitignore is respected
- [ ] Links work (no broken references)

## Questions?

Open a GitHub Discussion or Issue. We're here to help! 🤝

---

Thank you for making TalkSense better!
