import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private func makeShield() -> ShieldConfiguration {
        let label: String
        if #available(iOS 26.5, *) { label = "고요에서 기다리기" }
        else { label = "닫기 · 홈에서 고요를 여세요" }
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(red: 0.04, green: 0.1, blue: 0.18, alpha: 1),
            icon: UIImage(systemName: "moon.circle.fill"),
            title: .init(text: "잠깐, 고요", color: .white),
            subtitle: .init(text: "고요 앱의 ‘앱 잠금’ 탭에서 \(Shared.settings.waitSeconds)초 기다린 뒤 사용할 수 있습니다.", color: .white),
            primaryButtonLabel: .init(text: label, color: .black),
            primaryButtonBackgroundColor: .systemMint,
            secondaryButtonLabel: .init(text: "사용하지 않기", color: .white)
        )
    }
    override func configuration(shielding application: Application) -> ShieldConfiguration { makeShield() }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { makeShield() }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { makeShield() }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { makeShield() }
}
