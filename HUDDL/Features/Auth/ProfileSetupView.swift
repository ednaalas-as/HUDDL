import SwiftUI

/// PROFILE SETUP (635:2907) — step 2 of 2.
struct ProfileSetupView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ToastCenter.self) private var toasts
    let onDone: () -> Void

    @State private var photo: UIImage?
    @State private var sports: Set<Sport> = []
    @State private var skill: SkillLevel = .intermediate
    @State private var area: HomeArea = Geo.lucena
    @State private var showPhoto = false
    @State private var showArea = false
    @State private var saving = false

    var body: some View {
        ZStack {
            GlowBackground(showsAccent: false)
            ScrollView {
                VStack(spacing: 16) {
                    Wordmark(height: 50).padding(.top, 14)
                    card
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .overlay { if saving { LoadingOverlay(text: "Saving your profile…") } }
        .sheet(isPresented: $showPhoto) {
            PhotoSourceSheet(allowsRemove: photo != nil, onImage: { photo = $0 }, onRemove: { photo = nil })
        }
        .sheet(isPresented: $showArea) { HomeAreaSheet(current: area) { area = $0 } }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text("STEP 2 OF 2").font(HFont.inter(11, .semibold)).tracking(1).foregroundStyle(HColor.accentTag).padding(.top, 23)
            Text("Set up your profile").font(.system(size: 26, weight: .semibold)).foregroundStyle(.black).padding(.top, 4)
            Text("So we can match you with the right games nearby.").font(HFont.inter(12, .medium)).foregroundStyle(HColor.body)
                .multilineTextAlignment(.center).padding(.top, 6)

            Button { showPhoto = true } label: {
                ZStack {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(Circle())
                    } else {
                        Circle().fill(Color.white.opacity(0.7)).frame(width: 80, height: 80)
                            .overlay(Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(HColor.brandNavy.opacity(0.25)))
                        Image(systemName: "camera.fill").font(.system(size: 24)).foregroundStyle(HColor.brandNavy)
                    }
                }
            }
            .accessibilityLabel("Add photo")
            .padding(.top, 20)
            Button(photo == nil ? "Add photo" : "Change photo") { showPhoto = true }
                .font(HFont.inter(12, .semibold)).foregroundStyle(HColor.accentTag).padding(.top, 6)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Sports you play").padding(.top, 20)
                SportChipsGrid(selected: $sports)
                SectionLabel(text: "Skill level").padding(.top, 18)
                HStack(spacing: 8) {
                    ForEach(SkillLevel.allCases) { level in
                        SelectChip(text: level.title, isOn: skill == level) { skill = level }
                    }
                }
                SectionLabel(text: "Home area").padding(.top, 18)
                Button { showArea = true } label: {
                    HStack {
                        Text(area.name == Geo.lucena.name ? "Lucena City, Quezon" : area.name)
                            .font(HFont.rounded(17)).foregroundStyle(HColor.darkText)
                        Spacer()
                        Image(systemName: "mappin.circle.fill").foregroundStyle(HColor.brandNavy)
                    }
                    .padding(.horizontal, 16).frame(height: 50)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: HRadius.field))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 23)

            NavyButton(title: "CONTINUE", width: nil, isLoading: saving) { save(skip: false) }
                .padding(.horizontal, 23).padding(.top, 24)
            Button("Skip for now") { save(skip: true) }
                .font(HFont.inter(12, .semibold)).foregroundStyle(HColor.secondary).padding(.vertical, 16)
        }
        .frame(maxWidth: 380)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: HRadius.card))
        .background(Color.white.opacity(0.44), in: RoundedRectangle(cornerRadius: HRadius.card))
        .overlay(RoundedRectangle(cornerRadius: HRadius.card).stroke(Color.white.opacity(0.8), lineWidth: 1))
        .shadow(color: HColor.shadow.opacity(0.06), radius: 10, y: 6)
    }

    private func save(skip: Bool) {
        if !skip && sports.isEmpty { toasts.error("Pick at least one sport you play"); return }
        saving = true
        Task {
            do {
                var url: String?
                if let photo, !skip { url = try await StorageService.uploadImage(photo, folder: .avatars, maxDimension: 800) }
                let ordered = Sport.allCases.filter { sports.contains($0) }.map { SportSkill(sport: $0, skill: skill) }
                try await session.completeProfile(displayName: session.user?.displayName ?? session.user?.username ?? "Player",
                                                  sports: skip ? [] : ordered, homeArea: area, photoURL: url)
                onDone()
            } catch {
                toasts.error(AppError.message(error))
            }
            saving = false
        }
    }
}
