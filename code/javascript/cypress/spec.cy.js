
Cypress.Commands.add('waitForElement', (selector, text, interval = 5000) => {
  const checkElement = () => {
    cy.get('body').then($body => {
      if ($body.find(`${selector}:contains("${text}")`).length > 0) {
        return; // Element is found, stop the recursion
      } else {
        cy.wait(interval).then(checkElement); // Wait for the interval and check again
      }
    });
  };

  checkElement();
});

const primary = ".some-class"

describe('Set Session Storage Before Visiting Site', () => {
  it('should set session storage and then visit the site', () => {
    const sessionStorageKey = 'auth';
    const sessionStorageValue = '';

    cy.visit('https://some-site.com', {
      onBeforeLoad: (win) => {
        win.sessionStorage.setItem(sessionStorageKey, sessionStorageValue);
      }
    });

    cy.window().then((win) => {
      expect(win.sessionStorage.getItem(sessionStorageKey)).to.equal(sessionStorageValue);
    });

    cy.wait(25000);

    function performCalculationAndCheck() {
      cy.get('[data-testid=button-primary-outline]').contains('Calculate').click();
      cy.get(primary).first().click();
      cy.get('[data-testid=button-primary]').contains('Calculate').click();
      cy.get('[data-testid=button-primary]').contains('Done').click();
      cy.get('tbody tr:first a').click();
      cy.wait(20000);

      cy.waitForElement('div:contains("Status")', 'Completed');
      cy.get('div').filter('[style*="transform: none;"]').contains('Calculation').click();
      cy.wait(2000);

      cy.contains('div', 'Rejected')
        .parent()
        .find('.value')
        .invoke('text')
        .then((text) => {
          cy.log(`Rejected value is: ${text}`);
          expect(text.trim()).to.equal('0');
          cy.get('.cal-dashboard-header')
            .parent()
            .find('span')
            .contains('Back')
            .click();
          cy.wait(2000);
          performCalculationAndCheck();
        });

    }
    performCalculationAndCheck();
  });
});

