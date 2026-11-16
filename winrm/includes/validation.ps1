function Invoke-ValidationScripts($configuration)
{
    $validationScripts = $configuration.validationScripts
    Invoke-LocalScriptList $configuration $validationScripts
}
