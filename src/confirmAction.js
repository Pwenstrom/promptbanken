// Två-stegs bekräftelse för destruktiva knappar.
//
// Samma mönster som admin.js redan använder för "Ta bort prompt": första
// klicket byter etikett och färg, andra klicket utför. Ingen
// window.confirm -- den blockerar sidan och ser ut som ett webbläsarfel
// snarare än som ett val användaren gör i gränssnittet.
//
// Bekräftelsen faller tillbaka av sig själv efter RESET_MS, så en knapp
// som råkats klickas på inte blir liggande i "skarpt" läge.

const RESET_MS = 4000;

export function wireConfirmButton(button, { confirmLabel = 'Bekräfta radering?', onConfirm }) {
    const originalLabel = button.textContent;
    let timer = null;

    const reset = () => {
        button.dataset.deleteConfirm = '0';
        button.textContent = originalLabel;
        button.classList.remove('is-confirming');
        if (timer) {
            clearTimeout(timer);
            timer = null;
        }
    };

    button.addEventListener('click', async () => {
        if (button.dataset.deleteConfirm !== '1') {
            button.dataset.deleteConfirm = '1';
            button.textContent = confirmLabel;
            button.classList.add('is-confirming');
            timer = setTimeout(reset, RESET_MS);
            return;
        }

        reset();
        button.disabled = true;
        try {
            await onConfirm();
        } finally {
            // Lyckad radering ritar om listan och tar bort noden -- då
            // finns knappen inte kvar att låsa upp.
            if (button.isConnected) button.disabled = false;
        }
    });
}
