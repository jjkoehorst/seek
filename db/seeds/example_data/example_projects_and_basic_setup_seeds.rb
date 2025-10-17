# Project, Institution, Workgroup, Program, Strains, Organisms
program = Programme.where(title: 'Default Programme').first_or_create(web_page: 'http://www.seek4science.org', funding_details: 'Funding H2020X01Y001', description: 'This is a test programme for the SEEK sandbox.')
project = Project.where(title: 'Default Project').first_or_create(:programme_id => program.id, description: 'A description for the default project') # TODO this link is not working
institution = Institution.where(title: 'Default Institution').first_or_create(country: 'United Kingdom')
workgroup = WorkGroup.where(project_id: project.id, institution_id: institution.id).first_or_create

# Create a strain
strain = Strain.where(title: 'Sulfolobus solfataricus strain 98/2').first_or_create
strain.projects = [project]
strain.policy = Policy.create(name: 'publicly downloadable policy', sharing_scope: Policy::EVERYONE, access_type: Policy::ACCESSIBLE)
strain.organism = Organism.where(title: 'Sulfolobus solfataricus').first_or_create
strain.provider_name = 'BacDive'
strain.provider_id = '123456789'
strain.synonym = '98/2'
strain.comment = 'This is a test strain.'
# Note: contributor and tags will be added in example_users_seeds.rb after users are created
strain.save!
puts 'Seeded 1 strain.'

# Create an organism
organism = Organism.where(title: 'Sulfolobus solfataricus').first_or_create
organism.projects = [project]
organism.strains = [strain]
organism.concept_uri = '2287'  # Will be converted to http://purl.bioontology.org/ontology/NCBITAXON/2287
organism.save!
puts 'Seeded 1 organism.'

# Store references for other seed files
$program = program
$project = project
$institution = institution
$workgroup = workgroup
$strain = strain
$organism = organism