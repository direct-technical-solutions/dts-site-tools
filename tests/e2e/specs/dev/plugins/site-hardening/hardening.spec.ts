import { expect, test } from '@playwright/test';
import { ADMIN_STORAGE_STATE } from '../../helpers/admin-session';

// Protects what the Site Hardening plugin does in the admin (plan step 8a, D26): Application
// Passwords are off, so no program can log in to the REST API around two-factor login
// (docs/SITE_CHECKLIST.md 4.7). The headers are checked on every page in generic/theme.spec.ts;
// XML-RPC, the X-Pingback header, the version comments and the PHP version header in
// tests/scenario/plugins/site-hardening/dev-site-hardening.sh. And WordPress's emoji support is
// gone from the admin (visitor pages, embeds, the feed and email in the same scenario).
// WordPress's own id for the section on the profile page (wp-admin/user-edit.php, 7.1).
const APPLICATION_PASSWORDS_SECTION = '#application-passwords-section';
// What WordPress 7.1 prints for its emoji support in the admin (wp-includes/formatting.php): the
// detection script's settings tag and the emoji styles.
const EMOJI_SETTINGS = 'script#wp-emoji-settings';
const EMOJI_STYLES = 'style#wp-emoji-styles-inline-css';

// Starts with the dev admin's login, saved once per run by admin.setup.ts.
test.use({ storageState: ADMIN_STORAGE_STATE });

test('the profile page offers no Application Passwords', async ({ page }) => {
	await page.goto('/wp-admin/profile.php');
	// The page itself must have loaded, or the missing section would prove nothing.
	await expect(page.locator('#your-profile'), 'the profile form').toBeVisible();
	await expect(page.locator(APPLICATION_PASSWORDS_SECTION), 'the Application Passwords section').toHaveCount(0);
});

test('the admin carries no emoji script or styles', async ({ page }) => {
	await page.goto('/wp-admin/');
	// The dashboard must have loaded to its end, where the script is printed, or a missing tag
	// would prove nothing.
	await expect(page.locator('#dashboard-widgets'), 'the dashboard widgets').toBeVisible();
	await expect(page.locator('#wpfooter'), 'the admin footer').toBeAttached();
	await expect(page.locator(EMOJI_SETTINGS), 'the emoji detection settings').toHaveCount(0);
	await expect(page.locator(EMOJI_STYLES), 'the emoji styles').toHaveCount(0);
});
