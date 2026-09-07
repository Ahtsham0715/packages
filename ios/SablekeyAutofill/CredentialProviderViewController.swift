import AuthenticationServices
import UIKit

/// Sablekey's iOS AutoFill credential provider.
///
/// The vault itself cannot be opened here — see `SablekeyMirror` for why — so
/// this reads the biometric-gated login mirror the app writes. Everything the
/// extension can reach is behind a Face ID / Touch ID check enforced by the
/// Keychain, not by this code: `loadKey` simply fails if the user does not
/// authenticate.
class CredentialProviderViewController: ASCredentialProviderViewController {

    private var entries: [SablekeyMirror.Entry] = []
    private var filtered: [SablekeyMirror.Entry] = []
    private var serviceIdentifiers: [ASCredentialServiceIdentifier] = []

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let messageLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1)
        setUpViews()
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        self.serviceIdentifiers = serviceIdentifiers
        loadMirror()
    }

    /// The zero-interaction path: iOS asks for a credential without showing UI.
    ///
    /// Always declined with `userInteractionRequired`, which makes iOS present
    /// the extension properly and run the biometric check. Silently returning a
    /// password here would defeat the whole point of gating the mirror.
    override func provideCredentialWithoutUserInteraction(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue
            )
        )
    }

    override func prepareInterfaceToProvideCredential(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        serviceIdentifiers = [credentialIdentity.serviceIdentifier]
        loadMirror(preselecting: credentialIdentity.recordIdentifier)
    }

    // MARK: - Data

    private func loadMirror(preselecting recordIdentifier: String? = nil) {
        do {
            entries = try SablekeyMirror.read(
                reason: "Unlock to fill a saved login"
            )
        } catch SablekeyMirror.MirrorError.noKey {
            showMessage(
                "Autofill has not been set up yet.\n\nOpen Sablekey, unlock your "
                    + "vault, and turn on iOS AutoFill in Settings."
            )
            return
        } catch {
            // A biometric failure lands here too. Deliberately vague: the
            // extension should not distinguish "wrong face" from "no data".
            showMessage("Could not unlock your logins.")
            return
        }

        if let recordIdentifier,
           let match = entries.first(where: { $0.id == recordIdentifier }) {
            complete(with: match)
            return
        }

        applyFilter()
    }

    /// Narrows the list to entries whose stored URI matches the requesting app
    /// or page, keeping exact host matches above same-domain ones.
    private func applyFilter() {
        let targets = serviceIdentifiers.map(\.identifier)

        if targets.isEmpty {
            filtered = entries
        } else {
            filtered = entries.filter { entry in
                entry.uris.contains { uri in
                    targets.contains { SablekeyMirror.matches(uri: uri, target: $0) }
                }
            }
            if filtered.isEmpty {
                // Better to show everything than to show nothing: the user can
                // still pick, and a wrong guess by the matcher should not make
                // the vault look empty.
                filtered = entries
            } else {
                let primary = targets.first ?? ""
                filtered.sort { left, right in
                    let leftExact = left.uris.contains {
                        SablekeyMirror.host(of: $0) == SablekeyMirror.host(of: primary)
                    }
                    let rightExact = right.uris.contains {
                        SablekeyMirror.host(of: $0) == SablekeyMirror.host(of: primary)
                    }
                    if leftExact != rightExact { return leftExact }
                    return left.name.lowercased() < right.name.lowercased()
                }
            }
        }

        messageLabel.isHidden = !filtered.isEmpty
        tableView.isHidden = filtered.isEmpty
        if filtered.isEmpty {
            showMessage("No saved logins yet.")
        }
        tableView.reloadData()
    }

    private func complete(with entry: SablekeyMirror.Entry) {
        let credential = ASPasswordCredential(
            user: entry.username,
            password: entry.password
        )
        extensionContext.completeRequest(withSelectedCredential: credential)
    }

    // MARK: - Views

    private func setUpViews() {
        let cancel = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        let bar = UINavigationBar()
        let navItem = UINavigationItem(title: "Sablekey")
        navItem.leftBarButtonItem = cancel
        bar.setItems([navItem], animated: false)
        bar.barTintColor = UIColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1)
        bar.titleTextAttributes = [.foregroundColor: UIColor.white]
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.textColor = UIColor(white: 0.7, alpha: 1)
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.isHidden = true
        view.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func showMessage(_ text: String) {
        messageLabel.text = text
        messageLabel.isHidden = false
        tableView.isHidden = true
    }

    @objc private func cancelTapped() {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userCanceled.rawValue
            )
        )
    }
}

extension CredentialProviderViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let entry = filtered[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = entry.name
        content.secondaryText = entry.username
        content.textProperties.color = .white
        content.secondaryTextProperties.color = UIColor(white: 0.65, alpha: 1)
        cell.contentConfiguration = content
        cell.backgroundColor = .clear

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        complete(with: filtered[indexPath.row])
    }
}
