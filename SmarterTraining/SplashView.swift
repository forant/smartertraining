import SwiftUI

struct SplashView: View {
    @State private var opacity = 0.0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 27))

            HStack(spacing: 0) {
                Text("Smarter")
                    .fontWeight(.regular)
                Text("Training")
                    .fontWeight(.bold)
            }
            .font(.title2)

            Text("Training for people with real lives")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                opacity = 1.0
            }
        }
    }
}

#Preview {
    SplashView()
}
